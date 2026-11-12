import 'shop_profile.dart';

/// Single authoritative declaration of a shop profile's capabilities and
/// navigation visibility. All feature flags live here; ProfileCapabilities
/// and ProfileNavigation derive from it to avoid drift.
class ProfileDefinition {
  const ProfileDefinition({
    required this.showInventory,
    required this.trackStock,
    required this.measuredGoods,
    required this.variants,
    required this.drinkService,
    required this.layby,
    required this.jobs,
    required this.pooledCosts,
    required this.enhancedAnalytics,
  });

  final bool showInventory;
  final bool trackStock;
  final bool measuredGoods;
  final bool variants;
  final bool drinkService;
  final bool layby;
  final bool jobs;
  final bool pooledCosts;
  final bool enhancedAnalytics;

  static ProfileDefinition forProfile(ShopProfile profile) =>
      switch (profile) {
        ShopProfile.drinks => const ProfileDefinition(
            showInventory: true,
            trackStock: true,
            measuredGoods: true,
            variants: true,
            drinkService: true,
            layby: false,
            jobs: false,
            pooledCosts: false,
            enhancedAnalytics: true,
          ),
        ShopProfile.duka => const ProfileDefinition(
            showInventory: true,
            trackStock: true,
            measuredGoods: true,
            variants: false,
            drinkService: false,
            layby: false,
            jobs: false,
            pooledCosts: false,
            enhancedAnalytics: true,
          ),
        ShopProfile.fashion => const ProfileDefinition(
            showInventory: true,
            trackStock: true,
            measuredGoods: false,
            variants: true,
            drinkService: false,
            layby: true,
            jobs: false,
            pooledCosts: false,
            enhancedAnalytics: true,
          ),
        ShopProfile.open => const ProfileDefinition(
            showInventory: false,
            trackStock: true,
            measuredGoods: false,
            variants: false,
            drinkService: false,
            layby: false,
            jobs: true,
            pooledCosts: true,
            enhancedAnalytics: true,
          ),
      };
}

/// Shared feature switches for a shop profile.
///
/// This is configuration over the existing selling, inventory, finance and
/// analytics engines. It must not be used to select a different writer or
/// database schema.
class ProfileCapabilities {
  const ProfileCapabilities({
    required this.showInventory,
    required this.trackStock,
    required this.measuredGoods,
    required this.variants,
    required this.drinkService,
    required this.layby,
    required this.jobs,
    required this.pooledCosts,
    required this.enhancedAnalytics,
  });

  final bool showInventory;
  final bool trackStock;
  final bool measuredGoods;
  final bool variants;
  final bool drinkService;
  final bool layby;
  final bool jobs;
  final bool pooledCosts;
  final bool enhancedAnalytics;

  static ProfileCapabilities forProfile(ShopProfile profile) {
    final d = ProfileDefinition.forProfile(profile);
    return ProfileCapabilities(
      showInventory: d.showInventory,
      trackStock: d.trackStock,
      measuredGoods: d.measuredGoods,
      variants: d.variants,
      drinkService: d.drinkService,
      layby: d.layby,
      jobs: d.jobs,
      pooledCosts: d.pooledCosts,
      enhancedAnalytics: d.enhancedAnalytics,
    );
  }
}

extension ShopProfileCapabilities on ShopProfile {
  ProfileCapabilities get capabilities => ProfileCapabilities.forProfile(this);
  ProfileDefinition get definition => ProfileDefinition.forProfile(this);
}
