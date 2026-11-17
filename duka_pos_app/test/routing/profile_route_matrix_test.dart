// Route / profile matrix.
//
// Tests the redirect guard (appRedirect) for every profile × location
// combination. AppStageSnapshot is constructed directly — no database I/O,
// which is the supported way to test the guard.

import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/routing/app_redirect.dart';
import 'package:duka_pos/routing/app_stage_controller.dart';
import 'package:duka_pos/routing/routes.dart';
import 'package:duka_pos/services/app_stage.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:duka_pos/profile/profile_navigation.dart';
import 'package:duka_pos/services/roles.dart';
import '../support/harness.dart';

/// Builds an [AppStageSnapshot] for a profile × role, signed in and ready.
AppStageSnapshot snapshotFor({
  required ShopProfile profile,
  ShopRole role = ShopRole.admin,
}) {
  return AppStageSnapshot(
    stage: AppStage.ready,
    canManageStock: role != ShopRole.cashier,
    canViewReports: role != ShopRole.cashier,
    isAdmin: role == ShopRole.admin,
    shopProfile: profile,
  );
}

/// Expected redirect target: null means allowed, otherwise the path to redirect to.
String? expectedRedirect({
  required ShopProfile profile,
  required String location,
}) {
  // Profile capability guards
  if (location.startsWith('/open-business') && profile != ShopProfile.open) {
    return Routes.dashboard;
  }
  if (location.startsWith('/inventory/fashion-product') &&
      profile != ShopProfile.fashion) {
    return Routes.dashboard;
  }
  if (location == Routes.exchangeScreen && profile != ShopProfile.fashion) {
    return Routes.dashboard;
  }
  if (location == Routes.servings && !profile.navigation.showMeasuredGoods) {
    return Routes.dashboard;
  }
  if (location.startsWith('/inventory/tank') &&
      !profile.navigation.showDrinkService) {
    return Routes.dashboard;
  }
  return null;
}

void main() {
  group('profile route redirect guard', () {
    for (final profile in ShopProfile.values) {
      group(profile.displayName.toUpperCase(), () {
        // Shared routes always allowed for any signed-in profile.
        final List<String> sharedRoutes = <String>[
          Routes.dashboard,
          Routes.sell,
          Routes.inventory,
          Routes.analytics,
          Routes.settings,
          Routes.support,
          Routes.help,
          Routes.marketplace,
        ];

        for (final route in sharedRoutes) {
          testWidgets(
            '$route allowed under ${profile.displayName}',
            (WidgetTester tester) async {
              tester.useDevice(Device.compact);
              await loadAppFonts();

              final snapshot = snapshotFor(profile: profile);
              final result = appRedirect(
                snapshot: snapshot,
                location: route,
              );
              final expected =
                  expectedRedirect(profile: profile, location: route);
              expect(
                result,
                expected,
                reason:
                    '$route under ${profile.displayName}: expected $expected, got $result',
              );
            },
          );
        }

        // Profile-specific routes allowed under their own profile.

        if (profile == ShopProfile.fashion) {
          final List<String> fashionRoutes = <String>[
            Routes.fashionProductForm,
            Routes.fashionProduct(1),
            Routes.fashionProductEdit(1),
            Routes.exchangeScreen,
          ];
          for (final route in fashionRoutes) {
            testWidgets(
              'fashion route $route allowed',
              (WidgetTester tester) async {
                tester.useDevice(Device.compact);
                await loadAppFonts();

                final snapshot = snapshotFor(profile: profile);
                final result = appRedirect(
                  snapshot: snapshot,
                  location: route,
                );
                expect(
                  result,
                  isNull,
                  reason:
                      '$route under Fashion should be allowed (got $result)',
                );
              },
            );
          }
        }

        if (profile.navigation.showMeasuredGoods) {
          final List<String> measuredGoodsRoutes = <String>[Routes.servings];
          if (profile.navigation.showDrinkService) {
            measuredGoodsRoutes.addAll(<String>[
              Routes.tankRegister,
              Routes.tankDetail(1),
            ]);
          }
          for (final route in measuredGoodsRoutes) {
            testWidgets(
              'drinks route $route allowed',
              (WidgetTester tester) async {
                tester.useDevice(Device.compact);
                await loadAppFonts();

                final snapshot = snapshotFor(profile: profile);
                final result = appRedirect(
                  snapshot: snapshot,
                  location: route,
                );
                expect(
                  result,
                  isNull,
                  reason: '$route under Drinks should be allowed (got $result)',
                );
              },
            );
          }
        }

        // Cross-profile routes redirected to dashboard.
        for (final otherProfile in ShopProfile.values) {
          if (otherProfile == profile) continue;

          List<String> otherRoutes = <String>[];
          if (otherProfile == ShopProfile.fashion) {
            otherRoutes = <String>[
              Routes.fashionProductForm,
              Routes.exchangeScreen,
            ];
          }
          if (otherProfile.navigation.showDrinkService) {
            otherRoutes = <String>[Routes.tankRegister];
          }

          for (final route in otherRoutes) {
            testWidgets(
              '$route redirected under ${profile.displayName}',
              (WidgetTester tester) async {
                tester.useDevice(Device.compact);
                await loadAppFonts();

                final snapshot = snapshotFor(profile: profile);
                final result = appRedirect(
                  snapshot: snapshot,
                  location: route,
                );
                expect(
                  result,
                  Routes.dashboard,
                  reason:
                      '$route under ${profile.displayName} should redirect to dashboard (got $result)',
                );
              },
            );
          }
        }
      });
    }
  });
}
