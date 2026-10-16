// Resolving an ARB key held as a String.
//
// Why this file exists: a few things in this app are *enumerations that happen to
// be user-facing* — `AppDestination` names five tabs, `PosFailureCode` names nine
// failures — and they are declared `enum`, which cannot hold a `BuildContext`,
// a `Localizations` ancestor, or anything else resolved at paint time. The only
// option for a `const` enum member is to hold the KEY and let the widget that
// renders it do the lookup.
//
// That inverts the usual direction, which is why it needs its own file rather
// than a `byKey` on the generated class (which gen-l10n owns and will overwrite).
//
// The fallback is the important part. An unknown key returns ITSELF, not an empty
// string: `Text('')` is invisible and ships, while `Text('navDashbord')` is
// obviously wrong in a screenshot sweep. `keyResolutionIsTotal` below is asserted
// so a renamed key fails a test rather than a review.

import 'generated/app_localizations.dart';

/// Every runtime-resolved key in the catalogue, and nothing else.
extension AppLocalizationsKeys on AppLocalizations {
  /// The string for [key], or [key] itself when it is not in the catalogue.
  String byKey(String key) => switch (key) {
        'navDashboard' => navDashboard,
        'navDashboardShort' => navDashboardShort,
        'navSell' => navSell,
        'navSellShort' => navSellShort,
        'navInventory' => navInventory,
        'navInventoryShort' => navInventoryShort,
        'navAnalytics' => navAnalytics,
        'navAnalyticsShort' => navAnalyticsShort,
        'navSettings' => navSettings,
        'navSettingsShort' => navSettingsShort,
        'navSupport' => navSupport,
        'navSupportShort' => navSupportShort,
        _ => key,
      };

  /// The role line under the shop name: an owner is an owner, everyone else is a
  /// cashier. A method rather than a key so no call site has to spell the ternary
  /// — which is how two of them end up saying "Owner" for a manager.
  String roleLabel(bool isAdmin) =>
      isAdmin ? shellRoleOwner : settingsRoleCashier;

  /// Every key [byKey] can resolve, so a test can assert the mapping is TOTAL
  /// against the keys the enums actually use rather than against this file's own
  /// contents — a key present here but absent from the ARB would otherwise pass.
  static const List<String> resolvableKeys = <String>[
    'navDashboard',
    'navDashboardShort',
    'navSell',
    'navSellShort',
    'navInventory',
    'navInventoryShort',
    'navAnalytics',
    'navAnalyticsShort',
    'navSettings',
    'navSettingsShort',
    'navSupport',
    'navSupportShort',
  ];
}
