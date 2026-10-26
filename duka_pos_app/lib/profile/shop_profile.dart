/// The four authoritative SimpleSales business profiles.
///
/// Profiles are presets over the shared engines. They are stored per shop and
/// are deliberately not used as database/table names or sync identifiers.
enum ShopProfile {
  drinks,
  duka,
  fashion,
  open;

  String get wireValue => name;

  static ShopProfile fromWire(String? value) {
    return values.firstWhere(
      (profile) => profile.name == value,
      orElse: () => ShopProfile.duka,
    );
  }

  String get displayName => switch (this) {
        ShopProfile.drinks => 'Drinks',
        ShopProfile.duka => 'Duka',
        ShopProfile.fashion => 'Fashion',
        ShopProfile.open => 'Open',
      };

  String get description => switch (this) {
        ShopProfile.drinks => 'Measured drinks, pours, tabs and crates',
        ShopProfile.duka => 'Products, counted goods and everyday shop sales',
        ShopProfile.fashion => 'Styles, sizes, colours, lay-by and exchanges',
        ShopProfile.open => 'Money-first records with optional stock and jobs',
      };
}
