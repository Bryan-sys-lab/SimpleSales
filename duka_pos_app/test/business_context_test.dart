import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/profile/business_context.dart';
import 'package:duka_pos/profile/kesic_reference_2020.dart';
import 'package:duka_pos/profile/shop_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    await DatabaseHelper.openInMemoryForTests();
  });

  test('optional context round-trips without replacing POS profile', () async {
    final db = DatabaseHelper.instance;
    await db.setShopProfile(ShopProfile.duka);
    await db.saveBusinessContext(const BusinessContext(
      appProfile: 'duka',
      primaryActivityCode: '561030',
      primaryActivityStatus: 'selected',
      activityVersion: kesicReferenceVersion,
      secondaryActivityCodes: ['472110'],
      operatorRoles: ['retailer'],
      salesChannels: ['physical_shop'],
      countyCode: '047',
      settlementContext: 'urban',
      fieldProvenance: {'county_code': 'owner_confirmed'},
      confirmedAtUtc: '2026-11-19T00:00:00Z',
    ));

    final saved = await db.getBusinessContext();
    expect(await db.getShopProfile(), ShopProfile.duka);
    expect(saved.primaryActivityCode, '561030');
    expect(saved.appProfile, 'duka');
    expect(saved.activityScheme, 'KESIC');
    expect(saved.activityVersion, kesicReferenceVersion);
    expect(saved.secondaryActivityCodes, ['472110']);
    expect(saved.fieldProvenance['county_code'], 'owner_confirmed');
    final backup = await db.exportFullSnapshot();
    final domains = backup['domainTables'] as Map<String, List<String>>;
    expect(domains['profile'], contains('business_context'));
    final tables = backup['tables'] as Map<String, List<Map<String, Object?>>>;
    expect(tables['business_context']!.single['primary_activity_code'], '561030');
  });

  test('full backup restores business details into its own workspace', () async {
    final db = DatabaseHelper.instance;
    await db.setShopProfile(ShopProfile.fashion);
    await db.saveBusinessContext(const BusinessContext(
      appProfile: 'fashion',
      primaryActivityCode: '477110',
      primaryActivityStatus: 'selected',
      activityVersion: kesicReferenceVersion,
    ));
    final snapshot = await db.exportFullSnapshot();
    await db.saveBusinessContext(const BusinessContext(
      appProfile: 'duka',
      primaryActivityStatus: 'prefer_not_to_say',
    ));

    await db.restoreFullSnapshot(snapshot);

    final restored = await db.getBusinessContext();
    expect(restored.appProfile, 'fashion');
    expect(restored.primaryActivityCode, '477110');
    expect(restored.primaryActivityStatus, 'selected');
  });

  test('foreign-shop backup cannot overwrite business details', () async {
    final db = DatabaseHelper.instance;
    await db.saveBusinessContext(const BusinessContext(
      appProfile: 'fashion',
      primaryActivityStatus: 'prefer_not_to_say',
    ));
    final snapshot = await db.exportFullSnapshot();
    await db.saveBusinessContext(const BusinessContext(
      appProfile: 'duka',
      primaryActivityStatus: 'pending',
    ));
    final foreign = <String, Object?>{
      ...snapshot,
      'workspaceKey': 'another-shop',
    };

    await expectLater(
      db.restoreFullSnapshot(foreign),
      throwsA(isA<FormatException>()),
    );

    final current = await db.getBusinessContext();
    expect(current.appProfile, 'duka');
    expect(current.primaryActivityStatus, 'pending');
  });

  test('business context stores all four POS presets as separate values',
      () async {
    final db = DatabaseHelper.instance;
    for (final profile in ShopProfile.values) {
      await db.setShopProfile(profile);
      await db.saveBusinessContext(BusinessContext(
        appProfile: profile.wireValue,
        fieldProvenance: const {'app_profile': 'system_derived'},
      ));
      final context = await db.getBusinessContext();
      expect(context.appProfile, profile.wireValue);
      expect(await db.getShopProfile(), profile);
      expect(context.primaryActivityCode, isNull);
    }
  });

  test('changing POS profile keeps business context profile in sync', () async {
    final db = DatabaseHelper.instance;
    await db.saveBusinessContext(const BusinessContext(
      appProfile: 'duka',
      primaryActivityCode: '471110',
      primaryActivityStatus: 'selected',
      activityVersion: kesicReferenceVersion,
      fieldProvenance: {'primary_activity_code': 'owner_confirmed'},
    ));

    await db.setShopProfile(ShopProfile.fashion);

    final context = await db.getBusinessContext();
    expect(context.appProfile, 'fashion');
    expect(context.primaryActivityCode, '471110');
    expect(context.fieldProvenance['app_profile'], 'system_derived');
    expect(context.fieldProvenance['primary_activity_code'], 'owner_confirmed');
  });

  test('empty business context remains distinct from an activity', () async {
    final context = await DatabaseHelper.instance.getBusinessContext();
    expect(context.primaryActivityCode, isNull);
    expect(context.settlementContext, 'unknown');
    expect(context.primaryActivityStatus, 'pending');
  });

  test('version 89 upgrade creates the business context table', () async {
    final raw = await DatabaseHelper.instance.database;
    await raw.execute('DROP TABLE business_context');
    await DatabaseHelper.instance.upgradeSchema(raw, 89, 90);
    expect(await raw.query('business_context'), isEmpty);
  });

  test('secondary codes are capped, unique and cannot repeat the primary', () {
    expect(
      () => const BusinessContext(
        primaryActivityCode: '123',
        activityVersion: 'v1',
        secondaryActivityCodes: ['123'],
      ).validate(),
      throwsArgumentError,
    );
    expect(
      () => const BusinessContext(
        secondaryActivityCodes: ['1', '1'],
      ).validate(),
      throwsArgumentError,
    );
    expect(
      () => const BusinessContext(
        secondaryActivityCodes: ['1', '2', '3', '4', '5'],
      ).validate(),
      throwsArgumentError,
    );
  });

  test('controlled context values reject unsupported values', () {
    expect(
      () => const BusinessContext(settlementContext: 'estate').validate(),
      throwsArgumentError,
    );
  });

  test('unlisted KeSIC code stays pending and declined activity is distinct',
      () {
    const pending = BusinessContext(
      primaryActivityCode: '016190',
      primaryActivityStatus: 'pending',
      activityVersion: kesicReferenceVersion,
    );
    pending.validate();
    expect(pending.primaryActivityStatus, 'pending');

    const unlisted = BusinessContext(
      primaryActivityCode: '999999',
      primaryActivityStatus: 'pending',
      activityVersion: kesicReferenceVersion,
    );
    unlisted.validate();
    expect(unlisted.primaryActivityStatus, 'pending');

    expect(
      () => const BusinessContext(
        primaryActivityCode: '999999',
        primaryActivityStatus: 'selected',
        activityVersion: kesicReferenceVersion,
      ).validate(),
      throwsArgumentError,
    );

    const declined =
        BusinessContext(primaryActivityStatus: 'prefer_not_to_say');
    declined.validate();
    expect(declined.primaryActivityCode, isNull);
    expect(declined.primaryActivityStatus, 'prefer_not_to_say');
  });

  test('business profile completeness treats decline as complete, not missing',
      () {
    const declined = BusinessContext(
      primaryActivityStatus: 'prefer_not_to_say',
      settlementContext: 'prefer_not_to_say',
      countyCode: null,
      operatorRoles: [],
      salesChannels: [],
    );
    expect(declined.completeness.numerator, 2);
    expect(declined.completeness.denominator, 5);

    const complete = BusinessContext(
      primaryActivityCode: '561030',
      primaryActivityStatus: 'selected',
      countyCode: '047',
      settlementContext: 'urban',
      operatorRoles: ['retailer'],
      salesChannels: ['physical_shop'],
    );
    expect(complete.completeness, (numerator: 5, denominator: 5));
  });

  test('offline KeSIC index has distinct codes and all official sections', () {
    final codes = kesicActivities.map((activity) => activity.code).toSet();
    final sections = kesicActivities
        .map((activity) => activity.breadcrumb.split(' · ').first)
        .toSet();

    expect(kesicActivities.length, greaterThan(1100));
    expect(codes.length, kesicActivities.length);
    expect(kesicActivities.every((activity) =>
        RegExp(r'^\d{6}$').hasMatch(activity.code) &&
        activity.label.isNotEmpty &&
        activity.breadcrumb.contains('Division ')), isTrue);
    expect(sections, containsAll({
      for (final section in 'ABCDEFGHIJKLMNOPQRSTU'.split(''))
        'Section $section',
    }));
    expect(isCachedKesicCode('016190'), isFalse);
    expect(kesicAmbiguousCodes, contains('016190'));
    expect(isCachedKesicCode('999999'), isFalse);
    expect(isCachedKesicCode('016290'), isFalse);
  });
}
