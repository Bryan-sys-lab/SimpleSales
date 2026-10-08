import 'package:flutter/material.dart' show IconData, Icons;

import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n_keys.dart';

/// Every path in the app, in one place.
///
/// Call sites never hand-concatenate a URL. `Routes.staff(id)` and
/// `Routes.analytics` are the only strings the router and the screens agree on,
/// so a renamed path is a compile error rather than a deep link that 404s in the
/// field.
///
/// Identity always lives in a PATH PARAMETER, never in `state.extra`: `extra` is
/// a live Dart object, so it is `null` on a cold start from a deep link and after
/// process death. A screen that needs an id to rebuild reads it from
/// `state.pathParameters`, and treats `extra` as an optional fast path only.
abstract final class Routes {
  const Routes._();

  // ------------------------------------------------------------ the shell
  // Five branches. Reports is not one of them: it was a sixth tab whose content
  // overlapped Analytics closely enough that a cashier's "Reports" and a
  // manager's "Reports" opened different-looking screens with the same numbers.
  // It is now a view *inside* Analytics, at /analytics/reports.
  static const String dashboard = '/dashboard';
  static const String sell = '/sell';
  static const String inventory = '/inventory';
  static const String analytics = '/analytics';
  static const String settings = '/settings';

  /// Detail routes pushed on top of a branch. Each declares its parent as the
  /// `parentNavigatorKey` so it covers the shell — a sheet pushed from Settings
  /// should hide the navigation, not render inside a 320dp column.
  static const String shotCups = '/inventory/shot-cups';
  static const String shift = '/analytics/shift';
  static const String reports = '/analytics/reports';
  static const String taxSettings = '/settings/tax';
  static const String cameraScan = '/sell/scan';

  // ------------------------------------------------------------- the doors
  // Outside the shell: no navigation affordance, because there is no session to
  // navigate within.
  static const String splash = '/splash';
  static const String recovery = '/recovery';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String staffLogin = '/staff-login';
  static const String setup = '/setup';
  static const String onboarding = '/onboarding';

  /// Deep-link identity that must survive process death.
  static String product(String id) => '/inventory/product/$id';
  static const String productPattern = '/inventory/product/:productId';
  static const String staffPattern = '/settings/staff/:staffId';
  static String staff(String id) => '/settings/staff/$id';

  /// The root the app opens on. The splash is a real route so a cold deep link
  /// into `/login` still shows the boot gate before it is evaluated.
  static const String initial = splash;
}

/// The shell's destinations, in the order they appear in the navigation
/// affordance.
///
/// Named, never counted: the list is role-dependent, so a "jump to stock" link
/// has to say *where* rather than hold an index into a list whose shape changes
/// with the session. An index is how a low-stock tile ends up opening Settings.
enum AppDestination {
  dashboard('navDashboard', 'navDashboardShort'),
  sell('navSell', 'navSellShort',
      imageAsset:
          'assets/branding/stitch_simple_pos_launcher_icon/simple_pos_till_action_s_icon/screen.png'),
  inventory('navInventory', 'navInventoryShort'),
  analytics('navAnalytics', 'navAnalyticsShort'),
  settings('navSettings', 'navSettingsShort');

  const AppDestination(this.labelKey, this.shortLabelKey, {this.imageAsset});

  /// The ARB key for the permanent label.
  ///
  /// A KEY and not the string, because this used to be `const AppDestination(
  /// 'Dashboard')` — and an enum constant has no `BuildContext`, no
  /// `Localizations`, and therefore no way to be translated at all. Holding the
  /// key makes the label a lookup the widget performs rather than a value the
  /// enum froze at compile time, which is the only reason adding a locale is a
  /// translation task instead of a refactor.
  final String labelKey;

  /// The ARB key for the collapsed rail, where three words do not fit.
  final String shortLabelKey;

  final String? imageAsset;

  /// The permanent label, in the active locale.
  String label(AppLocalizations l10n) => l10n.byKey(labelKey);

  /// The collapsed-rail label, in the active locale.
  String shortLabel(AppLocalizations l10n) => l10n.byKey(shortLabelKey);

  String get path => switch (this) {
        AppDestination.dashboard => Routes.dashboard,
        AppDestination.sell => Routes.sell,
        AppDestination.inventory => Routes.inventory,
        AppDestination.analytics => Routes.analytics,
        AppDestination.settings => Routes.settings,
      };

  /// The glyph.
  ///
  /// One outline shape per destination, not an outlined/filled pair:
  /// `NavigationBar` already communicates selection with a pill and `w700` label,
  /// and a second silhouette adds nothing a screen reader can announce.
  IconData get icon => switch (this) {
        AppDestination.dashboard => Icons.space_dashboard_outlined,
        AppDestination.sell => Icons.point_of_sale_outlined,
        AppDestination.inventory => Icons.inventory_2_outlined,
        AppDestination.analytics => Icons.insights_outlined,
        AppDestination.settings => Icons.tune_outlined,
      };

  static AppDestination? fromPath(String path) {
    for (final AppDestination destination in AppDestination.values) {
      if (destination.path == path) return destination;
    }
    return null;
  }
}
