import 'shop_profile.dart';

/// Shared feature switches for a shop profile.
///
/// This is configuration over the existing selling, inventory, finance and
/// analytics engines. It must not be used to select a different writer or
/// database schema.
class ProfileCapabilities {
  const ProfileCapabilities({
    required this.trackStock,
    required this.measuredGoods,
    required this.variants,
    required this.drinkService,
    required this.layby,
    required this.jobs,
    required this.pooledCosts,
    required this.enhancedAnalytics,
  });

  final bool trackStock;
  final bool measuredGoods;
  final bool variants;
  final bool drinkService;
  final bool layby;
  final bool jobs;
  final bool pooledCosts;
  final bool enhancedAnalytics;

  static ProfileCapabilities forProfile(ShopProfile profile) =>
      switch (profile) {
        ShopProfile.drinks => const ProfileCapabilities(
            trackStock: true,
            measuredGoods: true,
            variants: false,
            drinkService: true,
            layby: false,
            jobs: false,
            pooledCosts: false,
            enhancedAnalytics: true,
          ),
        ShopProfile.duka => const ProfileCapabilities(
            trackStock: true,
            measuredGoods: true,
            variants: false,
            drinkService: false,
            layby: false,
            jobs: false,
            pooledCosts: false,
            enhancedAnalytics: true,
          ),
        ShopProfile.fashion => const ProfileCapabilities(
            trackStock: true,
            measuredGoods: false,
            variants: true,
            drinkService: false,
            layby: true,
            jobs: false,
            pooledCosts: false,
            enhancedAnalytics: true,
          ),
        ShopProfile.open => const ProfileCapabilities(
            trackStock: false,
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

extension ShopProfileCapabilities on ShopProfile {
  ProfileCapabilities get capabilities => ProfileCapabilities.forProfile(this);
}
