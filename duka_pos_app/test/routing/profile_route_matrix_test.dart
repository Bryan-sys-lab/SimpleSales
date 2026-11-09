import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:duka_pos/routing/app_redirect.dart';
import 'package:duka_pos/routing/app_stage_controller.dart';
import 'package:duka_pos/routing/routes.dart';
import 'package:duka_pos/services/app_stage.dart';

AppStageSnapshot snap(ShopProfile p) => AppStageSnapshot(
      stage: AppStage.ready,
      canManageStock: true,
      isAdmin: true,
      shopProfile: p,
    );

void main() {
  group('profile route matrix', () {
    test('open-business routes redirect non-open profiles', () {
      for (final p in [ShopProfile.drinks, ShopProfile.duka, ShopProfile.fashion]) {
        expect(appRedirect(snapshot: snap(p), location: Routes.openJobs), Routes.dashboard);
        expect(appRedirect(snapshot: snap(p), location: '/analytics/open-business/jobs/1'), Routes.dashboard);
      }
      expect(appRedirect(snapshot: snap(ShopProfile.open), location: Routes.openJobs), isNull);
    });

    test('fashion product routes redirect non-fashion profiles', () {
      for (final p in [ShopProfile.drinks, ShopProfile.duka, ShopProfile.open]) {
        expect(appRedirect(snapshot: snap(p), location: '/inventory/fashion-product/new'), Routes.dashboard);
        expect(appRedirect(snapshot: snap(p), location: '/fashion/exchange'), Routes.dashboard);
      }
      expect(appRedirect(snapshot: snap(ShopProfile.fashion), location: '/inventory/fashion-product/new'), isNull);
    });

    test('tank/servings routes redirect non-drinks profiles', () {
      for (final p in [ShopProfile.duka, ShopProfile.fashion, ShopProfile.open]) {
        expect(appRedirect(snapshot: snap(p), location: '/inventory/tank-register'), Routes.dashboard);
        expect(appRedirect(snapshot: snap(p), location: Routes.servings), Routes.dashboard);
      }
      expect(appRedirect(snapshot: snap(ShopProfile.drinks), location: '/inventory/tank-register'), isNull);
    });

    test('inventory redirects to portfolio for open profile', () {
      expect(appRedirect(snapshot: snap(ShopProfile.open), location: Routes.inventory), Routes.portfolio);
      expect(appRedirect(snapshot: snap(ShopProfile.duka), location: Routes.inventory), isNull);
    });
  });
}
