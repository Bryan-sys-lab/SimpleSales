import 'dart:convert';
import 'dart:io';

import '../profile/shop_profile.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import '../utils/money.dart';
import '../utils/units.dart';

/// Profile-specific seed data management.
/// 
/// Ensures seed data (like Blackbee) is only available for Drinks profile.
class ProfileSeedService {
  const ProfileSeedService();

  /// Checks if seed data import is allowed for the current profile.
  static bool isSeedImportAllowed(ShopProfile profile) {
    // Blackbee seed data is Drinks-only
    return profile == ShopProfile.drinks;
  }

  /// Imports Blackbee seed data for Drinks profile only.
  static Future<void> importBlackbeeSeed({
    required ShopProfile profile,
    required String filePath,
  }) async {
    if (profile != ShopProfile.drinks) {
      throw StateError('Blackbee seed data is only for Drinks profile');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw StateError('Seed file not found');
    }

    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    
    final db = DatabaseHelper.instance;
    await _importDrinksProducts(db, data);
  }

  static Future<void> _importDrinksProducts(
    DatabaseHelper db,
    Map<String, dynamic> data,
  ) async {
    final products = data['products'] as List<dynamic>? ?? [];
    
    for (final productData in products) {
      final product = Product(
        name: productData['name'] as String? ?? '',
        category: productData['category'] as String? ?? 'Drinks',
        costPrice: Money.fromMajor((productData['cost'] as num?)?.toDouble() ?? 0),
        sellPrice: Money.fromMajor((productData['price'] as num?)?.toDouble() ?? 0),
        stockQty: (productData['stock'] as num?)?.toDouble() ?? 0,
        reorderLevel: (productData['reorder_level'] as num?)?.toInt() ?? 5,
        bottleMl: (productData['bottle_ml'] as num?)?.toInt() ?? 750,
        unit: ProductUnit.parse(productData['unit'] as String?),
        halfPrice: (productData['half_price'] as num?) != null
            ? Money.fromMajor((productData['half_price'] as num).toDouble())
            : null,
        quarterPrice: (productData['quarter_price'] as num?) != null
            ? Money.fromMajor((productData['quarter_price'] as num).toDouble())
            : null,
        active: true,
        updatedAt: DateTime.now().toIso8601String(),
      );

      await db.upsertProduct(product);
    }
  }

  /// Gets profile-specific default categories.
  static List<String> getDefaultCategories(ShopProfile profile) {
    return switch (profile) {
      ShopProfile.drinks => [
        'Spirits',
        'Beer',
        'Wine',
        'Soft Drinks',
        'Water',
        'Mixers',
        'Snacks',
      ],
      ShopProfile.duka => [
        'Food',
        'Drinks',
        'Household',
        'Personal Care',
        'Stationery',
        'Other',
      ],
      ShopProfile.fashion => [
        'Tops',
        'Bottoms',
        'Dresses',
        'Outerwear',
        'Accessories',
        'Footwear',
      ],
      ShopProfile.open => [
        'Services',
        'Goods',
        'Materials',
        'Other',
      ],
    };
  }

  /// Gets profile-specific default units.
  static List<String> getDefaultUnits(ShopProfile profile) {
    return switch (profile) {
      ShopProfile.drinks => ['bottle', 'crate', 'keg', 'shot'],
      ShopProfile.duka => ['each', 'kg', 'litre', 'pack', 'carton'],
      ShopProfile.fashion => ['each', 'pair', 'set'],
      ShopProfile.open => ['each', 'hour', 'day', 'project'],
    };
  }

  /// Gets profile-specific onboarding suggestions.
  static Map<String, dynamic> getOnboardingSuggestions(ShopProfile profile) {
    return switch (profile) {
      ShopProfile.drinks => {
        'title': 'Set up your drinks menu',
        'steps': [
          'Add your spirits, beers and wines',
          'Set bottle sizes and prices',
          'Configure shot cups for measured pours',
          'Add crates and packs for bulk items',
        ],
        'example_products': [
          {'name': 'Tusker Lager', 'category': 'Beer', 'price': 200, 'unit': 'bottle'},
          {'name': 'Johnnie Walker', 'category': 'Spirits', 'price': 2500, 'unit': 'bottle'},
          {'name': 'Soda', 'category': 'Mixers', 'price': 100, 'unit': 'bottle'},
        ],
      },
      ShopProfile.duka => {
        'title': 'Set up your shop products',
        'steps': [
          'Add your everyday items',
          'Set prices and stock levels',
          'Organize by categories',
          'Add barcodes for scanning',
        ],
        'example_products': [
          {'name': 'Sugar 1kg', 'category': 'Food', 'price': 150, 'unit': 'pack'},
          {'name': 'Soap', 'category': 'Personal Care', 'price': 50, 'unit': 'each'},
          {'name': 'Exercise Book', 'category': 'Stationery', 'price': 30, 'unit': 'each'},
        ],
      },
      ShopProfile.fashion => {
        'title': 'Set up your fashion catalogue',
        'steps': [
          'Add styles and collections',
          'Create size and colour variants',
          'Set prices for each variant',
          'Configure lay-by options',
        ],
        'example_products': [
          {'name': 'T-shirt', 'category': 'Tops', 'price': 500, 'unit': 'each', 'has_variants': true},
          {'name': 'Jeans', 'category': 'Bottoms', 'price': 1200, 'unit': 'each', 'has_variants': true},
          {'name': 'Dress', 'category': 'Dresses', 'price': 2000, 'unit': 'each', 'has_variants': true},
        ],
      },
      ShopProfile.open => {
        'title': 'Set up your business records',
        'steps': [
          'Add items or services you sell',
          'Set prices (stock tracking is optional)',
          'Create cost groups for projects',
          'Set up jobs for customer work',
        ],
        'example_products': [
          {'name': 'Consultation hour', 'category': 'Services', 'price': 2000, 'unit': 'hour', 'optional_stock': false},
          {'name': 'Materials supply', 'category': 'Goods', 'price': 5000, 'unit': 'project', 'optional_stock': true},
          {'name': 'Installation service', 'category': 'Services', 'price': 10000, 'unit': 'project', 'optional_stock': false},
        ],
      },
    };
  }
}