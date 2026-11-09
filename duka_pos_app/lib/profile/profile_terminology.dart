import 'shop_profile.dart';
import '../l10n/generated/app_localizations.dart';

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

  static ProfileTerminology forProfile(ShopProfile profile, [AppLocalizations? l10n]) =>
      switch (profile) {
        ShopProfile.drinks => ProfileTerminology(
            product: l10n?.termDrinksProduct ?? 'Drink',
            productPlural: l10n?.termDrinksProductPlural ?? 'Drinks',
            sale: l10n?.termDrinksSale ?? 'Sale',
            stock: l10n?.termDrinksStock ?? 'Bar stock',
            primaryAction: l10n?.termDrinksPrimaryAction ?? 'Start sale',
          ),
        ShopProfile.duka => ProfileTerminology(
            product: l10n?.termDukaProduct ?? 'Product',
            productPlural: l10n?.termDukaProductPlural ?? 'Products',
            sale: l10n?.termDukaSale ?? 'Sale',
            stock: l10n?.termDukaStock ?? 'Stock',
            primaryAction: l10n?.termDukaPrimaryAction ?? 'Start sale',
          ),
        ShopProfile.fashion => ProfileTerminology(
            product: l10n?.termFashionProduct ?? 'Style',
            productPlural: l10n?.termFashionProductPlural ?? 'Styles',
            sale: l10n?.termFashionSale ?? 'Sale',
            stock: l10n?.termFashionStock ?? 'Catalogue',
            primaryAction: l10n?.termFashionPrimaryAction ?? 'Start sale',
          ),
        ShopProfile.open => ProfileTerminology(
            product: l10n?.termOpenProduct ?? 'Item or service',
            productPlural: l10n?.termOpenProductPlural ?? 'Items and services',
            sale: l10n?.termOpenSale ?? 'Record',
            stock: l10n?.termOpenStock ?? 'Optional stock',
            primaryAction: l10n?.termOpenPrimaryAction ?? 'Record sale',
          ),
      };
}

extension ShopProfileTerminology on ShopProfile {
  ProfileTerminology get terminology => ProfileTerminology.forProfile(this);
  ProfileTerminology terminologyLocalized(AppLocalizations l10n) => ProfileTerminology.forProfile(this, l10n);
}
