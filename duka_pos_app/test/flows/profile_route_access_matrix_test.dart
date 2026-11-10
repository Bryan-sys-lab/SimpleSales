import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/profile/profile_capabilities.dart';
import 'package:duka_pos/profile/profile_navigation.dart';
import 'package:duka_pos/profile/shop_profile.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Profile route access matrix', () {
    late DatabaseHelper db;

    setUp(() async {
      DatabaseHelper.resetForTests();
      db = await DatabaseHelper.openInMemoryForTests();
    });

    test('each profile exposes only its own navigation flags', () async {
      for (final profile in ShopProfile.values) {
        await db.setShopProfile(profile);
        final nav = profile.navigation;
        final def = profile.definition;

        // Navigation derives from definition
        expect(nav.showInventory, def.showInventory);
        expect(nav.showMeasuredGoods, def.measuredGoods);
        expect(nav.showVariants, def.variants);
        expect(nav.showDrinkService, def.drinkService);
        expect(nav.showLayby, def.layby);
        expect(nav.showJobs, def.jobs);
      }
    });

    test('Duka has variants disabled', () async {
      await db.setShopProfile(ShopProfile.duka);
      expect(ShopProfile.duka.capabilities.variants, isFalse);
      expect(ShopProfile.duka.navigation.showVariants, isFalse);
    });

    test('Fashion has variants enabled', () async {
      await db.setShopProfile(ShopProfile.fashion);
      expect(ShopProfile.fashion.capabilities.variants, isTrue);
      expect(ShopProfile.fashion.navigation.showVariants, isTrue);
    });

    test('Drinks has drinkService enabled', () async {
      await db.setShopProfile(ShopProfile.drinks);
      expect(ShopProfile.drinks.capabilities.drinkService, isTrue);
      expect(ShopProfile.drinks.navigation.showDrinkService, isTrue);
    });

    test('Open has jobs and pooledCosts enabled', () async {
      await db.setShopProfile(ShopProfile.open);
      expect(ShopProfile.open.capabilities.jobs, isTrue);
      expect(ShopProfile.open.capabilities.pooledCosts, isTrue);
      expect(ShopProfile.open.navigation.showJobs, isTrue);
    });

    test('Duka does not have drinkService', () async {
      await db.setShopProfile(ShopProfile.duka);
      expect(ShopProfile.duka.capabilities.drinkService, isFalse);
      expect(ShopProfile.duka.navigation.showDrinkService, isFalse);
    });

    test('Drinks does not have layby', () async {
      await db.setShopProfile(ShopProfile.drinks);
      expect(ShopProfile.drinks.capabilities.layby, isFalse);
      expect(ShopProfile.drinks.navigation.showLayby, isFalse);
    });
  });
}
