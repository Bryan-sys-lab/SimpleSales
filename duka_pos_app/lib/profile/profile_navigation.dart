import 'shop_profile.dart';
import 'profile_capabilities.dart';

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

  static ProfileNavigation forProfile(ShopProfile profile) {
    final d = ProfileDefinition.forProfile(profile);
    return ProfileNavigation(
      showInventory: d.showInventory,
      showMeasuredGoods: d.measuredGoods,
      showVariants: d.variants,
      showDrinkService: d.drinkService,
      showLayby: d.layby,
      showJobs: d.jobs,
    );
  }
}

extension ShopProfileNavigation on ShopProfile {
  ProfileNavigation get navigation => ProfileNavigation.forProfile(this);
}
