import 'shop_profile.dart';

/// Navigation capabilities for a shop profile.
///
/// Role permissions still decide whether a person may enter a destination.
/// This layer decides whether the destination belongs to the shop's profile at
/// all, keeping profile checks out of shared screens.
class ProfileNavigation {
  const ProfileNavigation({
    required this.showInventory,
    required this.showMeasuredGoods,
    required this.showVariants,
    required this.showDrinkService,
    required this.showLayby,
    required this.showJobs,
  });

  final bool showInventory;
  final bool showMeasuredGoods;
  final bool showVariants;
  final bool showDrinkService;
  final bool showLayby;
  final bool showJobs;

  static ProfileNavigation forProfile(ShopProfile profile) => switch (profile) {
        ShopProfile.drinks => const ProfileNavigation(
            showInventory: true,
            showMeasuredGoods: true,
            showVariants: false,
            showDrinkService: true,
            showLayby: false,
            showJobs: false,
          ),
        ShopProfile.duka => const ProfileNavigation(
            showInventory: true,
            showMeasuredGoods: true,
            showVariants: false,
            showDrinkService: false,
            showLayby: false,
            showJobs: false,
          ),
        ShopProfile.fashion => const ProfileNavigation(
            showInventory: true,
            showMeasuredGoods: false,
            showVariants: true,
            showDrinkService: false,
            showLayby: true,
            showJobs: false,
          ),
        ShopProfile.open => const ProfileNavigation(
            showInventory: false,
            showMeasuredGoods: false,
            showVariants: false,
            showDrinkService: false,
            showLayby: false,
            showJobs: true,
          ),
      };
}

extension ShopProfileNavigation on ShopProfile {
  ProfileNavigation get navigation => ProfileNavigation.forProfile(this);
}
