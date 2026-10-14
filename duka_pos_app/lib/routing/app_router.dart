import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/failure_recorder.dart';

import '../screens/analytics_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/database_error_screen.dart';
import '../screens/imports_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/login_screen.dart';
import '../screens/staff_login_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/owner_setup_screen.dart';
import '../screens/portfolio_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/sell_screen.dart';
import '../screens/activity_screen.dart';
import '../screens/diagnostics_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/shift_screen.dart';
import '../screens/shot_cups_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/tax_settings_screen.dart';
import '../widgets/camera_scan_screen.dart';
import '../screens/welcome_chooser_screen.dart';
import '../services/app_stage.dart';
import '../services/app_state.dart';
import '../theme/app_motion.dart';
import 'app_redirect.dart';
import 'app_stage_controller.dart';
import 'home_shell.dart';
import 'not_found_screen.dart';
import 'routes.dart';
import 'system_back_handler.dart';

/// The keys that decide WHO owns a route's Navigator.
///
/// The shell's branches each get their own navigator so `goBranch` keeps five
/// independent stacks alive at once. Everything that must cover the shell — a
/// sheet, the PIN pad, a 404 — declares the root key, or it renders inside a
/// rail's 176dp column.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

final List<GlobalKey<NavigatorState>> branchNavigatorKeys =
    List<GlobalKey<NavigatorState>>.generate(
  AppDestination.values.length,
  (int index) => GlobalKey<NavigatorState>(
    debugLabel: 'branch-${AppDestination.values[index].name}',
  ),
);

/// The one router for the whole app.
///
/// Constructed here and nowhere else. A second `GoRouter` fragments history,
/// deep links, and back-button behaviour; a feature registers its routes INTO
/// this list and never builds one of its own.
/// The app's one Back handler.
///
/// Held here rather than inside `_ThemedApp` because the guard that uses it is
/// built by each route's page, which is built by this file. The hint callback
/// is set by the app below its `MaterialApp`, where the localized sentence and a
/// `ScaffoldMessenger` both exist.
final SystemBackHandler systemBackHandler = SystemBackHandler(() {});

/// Replaces the handler's hint, which needs a context below the `MaterialApp`.
void setSystemBackHint(void Function() hint) => systemBackHandler.hint = hint;

GoRouter buildAppRouter({
  required AppStageController stage,
  required AppState appState,
}) {
  final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.initial,
    // The router re-evaluates `redirect` whenever this fires. Bridging the stage
    // controller is what makes the guard reactive: signing in moves the stage
    // without touching the boot flags, and a role change moves what a session may
    // reach without moving the stage at all. Polling would be the alternative and
    // it re-runs the guard on every frame.
    refreshListenable: stage,
    redirect: (BuildContext context, GoRouterState routerState) => appRedirect(
      snapshot: stage.snapshot,
      location: routerState.matchedLocation,
    ),
    errorBuilder: (BuildContext context, GoRouterState routerState) =>
        NotFoundScreen(location: routerState.matchedLocation),
    // Where the failure log's trail comes from. The observer receives the
    // recorder the app already owns, so navigation is a note and nothing else.
    observers: <NavigatorObserver>[
      _BreadcrumbObserver(failureRecorder),
    ],
    routes: <RouteBase>[
      ..._doorRoutes(stage, appState),
      ..._shellRoutes(),
    ],
  );
  _backRouter = router;
  return router;
}

/// Everything outside the shell: the boot gate and the four ways into a
/// session. A signed-out session has no branches to keep alive, and the PIN pad
/// must not inherit a rail from the last owner's session.
List<RouteBase> _doorRoutes(AppStageController stage, AppState appState) {
  return <RouteBase>[
    GoRoute(
      path: Routes.splash,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (BuildContext context, GoRouterState routerState) =>
          _fadeThrough(routerState, const SplashScreen()),
    ),
    GoRoute(
      path: Routes.recovery,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (BuildContext context, GoRouterState routerState) =>
          _fadeThrough(routerState, const DatabaseErrorScreen()),
    ),
    GoRoute(
      path: Routes.welcome,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (BuildContext context, GoRouterState routerState) =>
          _fadeThrough(
        routerState,
        WelcomeChooserScreen(
          shopName: appState.owner?.shopName ?? '',
          hasShop: appState.owner != null,
        ),
      ),
    ),
    GoRoute(
      path: Routes.login,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (BuildContext context, GoRouterState routerState) =>
          _fadeThrough(routerState, const LoginScreen()),
    ),
    GoRoute(
      path: Routes.staffLogin,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (BuildContext context, GoRouterState routerState) =>
          _fadeThrough(routerState, const StaffLoginScreen()),
    ),
    GoRoute(
      path: Routes.setup,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (BuildContext context, GoRouterState routerState) =>
          _fadeThrough(
        routerState,
        OwnerSetupScreen(
          isAdditionalShop: stage.intent == AppChooserIntent.addShop,
          carryOverFrom:
              stage.intent == AppChooserIntent.addShop ? appState.owner : null,
          onCancel: () {
            // Abandon the choice BEFORE navigating. The stage is derived from
            // the intent, so leaving the intent alone would make the guard pull
            // the user straight back into setup — the Back button appearing to
            // do nothing while the screen they left came back.
            stage.abandonChoice();
            context.go(Routes.welcome);
          },
        ),
      ),
    ),
    GoRoute(
      path: Routes.onboarding,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (BuildContext context, GoRouterState routerState) =>
          _fadeThrough(
        routerState,
        OnboardingScreen(onComplete: stage.completeOnboarding),
      ),
    ),
  ];
}

/// The shell and its five branches.
List<RouteBase> _shellRoutes() {
  return <RouteBase>[
    StatefulShellRoute.indexedStack(
      builder: (
        BuildContext context,
        GoRouterState routerState,
        StatefulNavigationShell navigationShell,
      ) =>
          HomeShell(navigationShell: navigationShell),
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          navigatorKey: branchNavigatorKeys[AppDestination.dashboard.index],
          routes: <RouteBase>[
            GoRoute(
              path: Routes.dashboard,
              pageBuilder: (BuildContext context, GoRouterState routerState) =>
                  _fadeThrough(routerState, const DashboardScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: branchNavigatorKeys[AppDestination.sell.index],
          routes: <RouteBase>[
            GoRoute(
              path: Routes.sell,
              pageBuilder: (BuildContext context, GoRouterState routerState) =>
                  _fadeThrough(routerState, const SellScreen()),
              routes: <RouteBase>[
                // Covers the shell: a scanner wants the whole screen, including
                // the navigation affordance it would otherwise hide behind.
                GoRoute(
                  path: 'scan',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder:
                      (BuildContext context, GoRouterState routerState) =>
                          _fadeThrough(routerState, const CameraScanScreen()),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: branchNavigatorKeys[AppDestination.inventory.index],
          routes: <RouteBase>[
            GoRoute(
              path: Routes.inventory,
              pageBuilder: (BuildContext context, GoRouterState routerState) =>
                  _fadeThrough(routerState, const InventoryScreen()),
              routes: <RouteBase>[
                // Identity in the PATH, so a cold deep link fully reconstructs the
                // screen. `extra` would be null after process death.
                GoRoute(
                  path: 'product/:productId',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder:
                      (BuildContext context, GoRouterState routerState) =>
                          _fadeThrough(
                    routerState,
                    InventoryScreen(
                      focusedProductId: routerState.pathParameters['productId'],
                    ),
                  ),
                ),
                GoRoute(
                  path: 'shot-cups',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder:
                      (BuildContext context, GoRouterState routerState) =>
                          _fadeThrough(routerState, const ShotCupsScreen()),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: branchNavigatorKeys[AppDestination.analytics.index],
          routes: <RouteBase>[
            GoRoute(
              path: Routes.analytics,
              pageBuilder: (BuildContext context, GoRouterState routerState) =>
                  _fadeThrough(routerState, const AnalyticsScreen()),
              routes: <RouteBase>[
                // Reports used to be a sixth tab reporting the same numbers
                // under a different name. It is a view inside Analytics now.
                GoRoute(
                  path: 'reports',
                  pageBuilder:
                      (BuildContext context, GoRouterState routerState) =>
                          _fadeThrough(
                    routerState,
                    const ReportsScreen(),
                  ),
                ),
                GoRoute(
                  path: 'shift',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder:
                      (BuildContext context, GoRouterState routerState) =>
                          _fadeThrough(routerState, const ShiftScreen()),
                ),
                // The all-shops view. A sibling of Reports rather than a tab:
                // it answers a question a single shop cannot, so it is only
                // offered where the answer exists.
                GoRoute(
                  path: 'portfolio',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder:
                      (BuildContext context, GoRouterState routerState) =>
                          _fadeThrough(routerState, const PortfolioScreen()),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: branchNavigatorKeys[AppDestination.settings.index],
          routes: <RouteBase>[
            GoRoute(
              path: Routes.settings,
              pageBuilder: (BuildContext context, GoRouterState routerState) =>
                  _fadeThrough(routerState, const SettingsScreen()),
              routes: <RouteBase>[
                GoRoute(
                  path: 'tax',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder:
                      (BuildContext context, GoRouterState routerState) =>
                          _fadeThrough(routerState, const TaxSettingsScreen()),
                ),
                // The owner's activity view. A child of Settings because that
                // is where an owner goes to look at what their shop is doing,
                // and a `push` target so the back button returns them to the
                // Settings scroll position they came from.
                GoRoute(
                  path: 'activity',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder:
                      (BuildContext context, GoRouterState routerState) =>
                          _fadeThrough(routerState, const ActivityScreen()),
                ),
                // Where the phone's own failure log is read. A child of
                // Settings for the same reason as Activity: an owner looks for
                // what went wrong where they look for everything else.
                // The wiring lives in the screen's own factory, so the router
                // stays a routing table and the feature decides what its data
                // is.
                GoRoute(
                  path: 'diagnostics',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder:
                      (BuildContext context, GoRouterState routerState) =>
                          _fadeThrough(routerState, DiagnosticsScreenOpen()),
                ),
                // The shop's own account: who is signed in, where it is
                // verified, and the avatar. A child of Settings for the same
                // reason as the other two — an owner looks for their own
                // account where they look for everything else.
                GoRoute(
                  path: 'profile',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder:
                      (BuildContext context, GoRouterState routerState) =>
                          _fadeThrough(routerState, const ProfileScreenOpen()),
                ),
                // The rows an import asked about. A child of Settings for the
                // same reason as the others — an owner looks for what needs
                // finishing where they look for everything else — and a `push`
                // target so Back returns them to the Settings scroll position.
                GoRoute(
                  path: 'imports',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder:
                      (BuildContext context, GoRouterState routerState) =>
                          _fadeThrough(routerState, const ImportsScreen()),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ];
}

/// Watches navigation so the failure log has a trail.
///
/// Without this, a crash in the sell screen is a crash in a screen nobody can
/// name, and a shop owner's description ("it broke when I was selling") is all
/// anyone has. With it, the last ten places the shop went are on the entry.
///
/// The trail is the recorder's own ring buffer, so this is a note and nothing
/// more — it does not read the router's state, hold a reference to it, or slow
/// a navigation down.
class _BreadcrumbObserver extends NavigatorObserver {
  _BreadcrumbObserver(this._recorder);

  final FailureRecorder _recorder;

  @override
  void didPush(Route<void> route, Route<void>? previousRoute) {
    final String location = _locationOf(route);
    _recorder.jot('navigated $location');
    // Also set the context: a failure recorded a moment later should say WHERE
    // it happened, and without this the route column of the log was always null
    // because nothing else knew the current route.
    _recorder.context.route = location;
  }

  @override
  void didPop(Route<void> route, Route<void>? previousRoute) {
    final String location = _locationOf(previousRoute);
    _recorder.jot('back to $location');
    _recorder.context.route = location;
  }

  /// The route's settings name, which is where a screen's identity lives.
  ///
  /// A route with no name is described by its type — `_ModalScopeState`, say,
  /// which is useless — so an unnamed route records nothing rather than
  /// recording noise.
  String _locationOf(Route<void>? route) {
    final String? name = route?.settings.name;
    if (name != null && name.isNotEmpty) return name;
    final String kind = route?.runtimeType.toString() ?? 'unknown';
    return kind.replaceAll('_', '').toLowerCase();
  }
}

/// The app's one transition: a short fade-through.
///
/// Collapsed to nothing when the OS has asked for reduced motion — read at
/// page-build time from `MediaQuery`, because `transitionsBuilder` has no
/// context of its own to read from.
///
/// Deliberately not a slide. A horizontal push on a POS reads as "the screen
/// moved sideways", which at a counter is one more thing to interpret between
/// the customer and the sale.
/// The router the guard pops, held once.
///
/// A module-level reference rather than a parameter: every route's page builder
/// goes through [_fadeThrough] and none of them has the router in scope, while
/// the router exists exactly once. Assigned when it is built and read only from
/// a back press.
GoRouter? _backRouter;

/// The router [systemBackHandler] pops.
///
/// Assigned by [buildAppRouter] and by a test that drives the real dispatch
/// path. A module-level reference because the guard is built per page and none
/// of those builders has the router in scope.
set appRouterForTesting(GoRouter? value) => _backRouter = value;

/// The page every route is built with, for a test that needs the REAL dispatch
/// path — the guard is installed by this function, so a test that builds its own
/// pages would prove nothing about it.
CustomTransitionPage<void> fadeThroughForTesting(
  GoRouterState routerState,
  Widget child,
) =>
    _fadeThrough(routerState, child);

CustomTransitionPage<void> _fadeThrough(
  GoRouterState routerState,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: routerState.pageKey,
    // EVERY page goes through here, so this is the one place the guard can live
    // and still cover all of them. A `PopScope` built by a route is inside the
    // router's subtree and registers after the router does, so it wins the
    // dispatch — which is what makes back answerable at all, where the same
    // `PopScope` above `MaterialApp.router` was proved inert.
    child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        final GoRouter? router = _backRouter;
        if (router != null) systemBackHandler.handle(router, didPop: didPop);
      },
      child: child,
    ),
    transitionDuration: AppMotion.standard.normal,
    reverseTransitionDuration: AppMotion.standard.fast,
    transitionsBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget page,
    ) {
      if (MediaQuery.disableAnimationsOf(context)) return page;
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: AppMotion.standard.emphasized,
        ),
        child: page,
      );
    },
  );
}

/// The app's one router, as a provider.
///
/// `ref.watch` on both dependencies so a role change rebuilds the router with the
/// new session's route set — which matters because the route *list* is
/// role-independent but the redirect's answer is not.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>(
  create: (BuildContext context) => buildAppRouter(
    stage: context.read<AppStageController>(),
    appState: context.read<AppState>(),
  ),
);
