import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../screens/analytics_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/database_error_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/login_screen.dart';
import '../screens/staff_login_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/owner_setup_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/sell_screen.dart';
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
GoRouter buildAppRouter({
  required AppStageController stage,
  required AppState appState,
}) {
  return GoRouter(
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
    routes: <RouteBase>[
      ..._doorRoutes(stage, appState),
      ..._shellRoutes(),
    ],
  );
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
          onCancel: stage.intent == AppChooserIntent.addShop
              ? () => context.go(Routes.welcome)
              : null,
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
                    const ReportsScreen(embedded: true),
                  ),
                ),
                GoRoute(
                  path: 'shift',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder:
                      (BuildContext context, GoRouterState routerState) =>
                          _fadeThrough(routerState, const ShiftScreen()),
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
              ],
            ),
          ],
        ),
      ],
    ),
  ];
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
CustomTransitionPage<void> _fadeThrough(
  GoRouterState routerState,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: routerState.pageKey,
    child: child,
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
