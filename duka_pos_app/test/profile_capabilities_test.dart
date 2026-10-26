import 'package:duka_pos/profile/profile_capabilities.dart';
import 'package:duka_pos/profile/profile_analytics.dart';
import 'package:duka_pos/profile/profile_navigation.dart';
import 'package:duka_pos/profile/profile_terminology.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all profiles expose the shared analytics engine', () {
    for (final profile in ShopProfile.values) {
      expect(profile.capabilities.enhancedAnalytics, isTrue);
    }
  });

  test('profile capabilities keep profile-specific behavior declarative', () {
    expect(ShopProfile.drinks.capabilities.drinkService, isTrue);
    expect(ShopProfile.fashion.capabilities.variants, isTrue);
    expect(ShopProfile.duka.capabilities.variants, isFalse);
    expect(ShopProfile.open.capabilities.jobs, isTrue);
    expect(ShopProfile.open.capabilities.pooledCosts, isTrue);
    expect(ShopProfile.duka.capabilities.trackStock, isTrue);
  });

  test('terminology is selected through the profile layer', () {
    expect(ShopProfile.drinks.terminology.productPlural, 'Drinks');
    expect(ShopProfile.fashion.terminology.stock, 'Catalogue');
    expect(ShopProfile.open.terminology.sale, 'Record');
  });

  test('navigation is profile-driven while permissions remain separate', () {
    expect(ShopProfile.drinks.navigation.showInventory, isTrue);
    expect(ShopProfile.fashion.navigation.showVariants, isTrue);
    expect(ShopProfile.open.navigation.showInventory, isFalse);
    expect(ShopProfile.open.navigation.showJobs, isTrue);
  });

  test('analytics emphasis uses the shared KPI vocabulary', () {
    expect(
      ShopProfile.drinks.analytics.emphasis,
      containsAll(<ProfileKpi>[ProfileKpi.litresSold, ProfileKpi.pourVariance]),
    );
    expect(
      ShopProfile.open.analytics.emphasis,
      containsAll(
          <ProfileKpi>[ProfileKpi.pooledCost, ProfileKpi.jobsCompleted]),
    );
  });
}
