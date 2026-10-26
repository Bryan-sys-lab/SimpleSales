import 'shop_profile.dart';

/// Profile-aware words used by shared screens. Stored values and API names
/// remain profile-neutral; only presentation changes here.
class ProfileTerminology {
  const ProfileTerminology({
    required this.product,
    required this.productPlural,
    required this.sale,
    required this.stock,
    required this.primaryAction,
  });

  final String product;
  final String productPlural;
  final String sale;
  final String stock;
  final String primaryAction;

  static ProfileTerminology forProfile(ShopProfile profile) =>
      switch (profile) {
        ShopProfile.drinks => const ProfileTerminology(
            product: 'Drink',
            productPlural: 'Drinks',
            sale: 'Sale',
            stock: 'Bar stock',
            primaryAction: 'Start sale',
          ),
        ShopProfile.duka => const ProfileTerminology(
            product: 'Product',
            productPlural: 'Products',
            sale: 'Sale',
            stock: 'Stock',
            primaryAction: 'Start sale',
          ),
        ShopProfile.fashion => const ProfileTerminology(
            product: 'Style',
            productPlural: 'Styles',
            sale: 'Sale',
            stock: 'Catalogue',
            primaryAction: 'Start sale',
          ),
        ShopProfile.open => const ProfileTerminology(
            product: 'Item or service',
            productPlural: 'Items and services',
            sale: 'Record',
            stock: 'Optional stock',
            primaryAction: 'Record sale',
          ),
      };
}

extension ShopProfileTerminology on ShopProfile {
  ProfileTerminology get terminology => ProfileTerminology.forProfile(this);
}
