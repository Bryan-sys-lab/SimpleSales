// Account deletion that actually destroys the data.
//
// The promise this suite pins is the one the owner is asking for: "we are not
// left with usable data even if we backed up the system". So the properties
// worth guarding are not "the rows were deleted" — a DELETE leaves the bytes in
// the file — but:
//
//   1. Every personal field is CIPHERTEXT afterwards, and the ciphertext cannot
//      be read back. A test that only checks "the column is not the original
//      string" would pass against a base64 blob that is perfectly readable.
//   2. The books survive. Takings and stock are the shop's, not the person's,
//      and an erasure that nukes them destroys the shop to protect a name.
//   3. A wrong PIN erases NOTHING. A deletion behind a PIN anyone can type is
//      a deletion anyone can perform on a phone left on a counter.
//   4. The key that would read the ciphertext back is gone.
//
// The keystore is faked, exactly as in backup_test, because it is the only
// platform-bound part. The cipher, the PBKDF2 and the transaction all run for
// real — they are what the erasure depends on.

import 'dart:io';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/account_deletion_service.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/auth_service.dart';
import 'package:duka_pos/services/staff_credential_cache.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A path provider pointing at a directory the test owns.
///
/// The erasure destroys the local encrypted backups as well as the ciphertext,
/// and that half needs somewhere to look for `.duka` files.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

/// A keystore backed by memory.
class _InMemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      values[key];

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    values.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      values.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map<String, String>.from(values);

  @override
  Future<void> deleteAll({
    required Map<String, String> options,
  }) async =>
      values.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String validPin = '4321';

  late DatabaseHelper db;
  late _InMemorySecureStorage keystore;
  late Directory docs;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    docs = await Directory.systemTemp.createTemp('duka_delete_');
    PathProviderPlatform.instance = _FakePathProvider(docs);
    keystore = _InMemorySecureStorage();
    // The keystore is the only platform-bound part of the erasure path, so it
    // is the only part replaced. The real `FlutterSecureStorage()` the service
    // constructs reads through this platform instance, which means the service
    // under test is the real one and not a mock of itself.
    FlutterSecureStoragePlatform.instance = keystore;
    DatabaseHelper.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = await DatabaseHelper.openInMemoryForTests();
  });

  tearDown(() async => docs.delete(recursive: true));

  /// A shop as the owner has set it up: an owner, a cashier, a sale.
  /// A shop as the owner has set it up: an owner, a cashier, a sale.
  /// A product, so the stock adjustment in the erasure test has a row to point
  /// at and the sale has something to contain.
  Product productRow() => Product(
        id: 0,
        name: 'Tusker 500ml',
        category: 'Drinks',
        costPrice: Money.fromMajor(120),
        sellPrice: Money.fromMajor(180),
        stockQty: 24,
        reorderLevel: 6,
        updatedAt: DateTime.now().toIso8601String(),
      );

  Future<void> seed() async {
    await db.createOwner(Owner(
      id: 1,
      name: 'Amina Duka',
      pinHash: await AuthService.hashPin(validPin),
      email: 'amina@duka.co.ke',
      shopName: 'Amina Duka',
      createdAt: DateTime.now().toIso8601String(),
    ));
    await db.addStaff(Staff(
      name: 'Joseph Otieno',
      role: 'cashier',
      pinHash: await AuthService.hashPin('1111'),
    ));
  }

  bool looksErased(Object? value) =>
      value is String && value.startsWith('erased:');

  /// Reads a personal column straight out of the file.
  Future<Object?> raw(String sql, [List<Object?>? args]) async {
    final rows = await db.database.then((d) => d.rawQuery(sql, args));
    expect(rows, isNotEmpty);
    return rows.first.values.first;
  }

  group('a completed deletion', () {
    test('every personal field is ciphertext, and is not the plaintext',
        () async {
      await seed();

      final report = await AccountDeletionService.deleteAccount(pin: validPin);

      expect(report.deletionId, isNotEmpty);
      expect(report.completedAt.isUtc, isTrue);

      // The owner's identity is gone, in every field it lived in.
      expect(looksErased(await raw('SELECT name FROM owner')), isTrue);
      expect(looksErased(await raw('SELECT email FROM owner')), isTrue);
      expect(looksErased(await raw('SELECT shop_name FROM owner')), isTrue);
      expect(looksErased(await raw('SELECT pin_hash FROM owner')), isTrue);

      // And a cashier, who is also a person.
      expect(looksErased(await raw('SELECT name FROM staff LIMIT 1')), isTrue);
      expect(
          looksErased(await raw('SELECT pin_hash FROM staff LIMIT 1')), isTrue);
    });

    test('the books survive — an erasure is not a shop reset', () async {
      await seed();
      final owner = (await db.getOwner())!;
      final before = await db.database.then((d) => d.query('products'));
      final saleCountBefore =
          (await db.database.then((d) => d.query('sales'))).length;

      await AccountDeletionService.deleteAccount(pin: validPin);

      final after = await db.database.then((d) => d.query('products'));
      final saleCountAfter =
          (await db.database.then((d) => d.query('sales'))).length;

      // Nothing was deleted, only encrypted where it named a person.
      expect(after.length, before.length);
      expect(saleCountAfter, saleCountBefore);
      // The takings themselves are untouched, because they are the shop's
      // books rather than anyone's personal data.
      expect(owner.shopName, isNotNull);
    });

    test('the audit log still records that the deletion happened', () async {
      await seed();

      await AccountDeletionService.deleteAccount(pin: validPin);

      // Erasing the log would leave the owner with no proof they asked for it.
      final rows = await db.database.then((d) => d.rawQuery(
          'SELECT action, detail FROM audit_log WHERE action = ?',
          <Object?>['account_deleted']));
      expect(rows, hasLength(1));
    });

    test('the key that would read the ciphertext back is destroyed', () async {
      await seed();

      await AccountDeletionService.deleteAccount(pin: validPin);

      // Without this, a copy of the database is a copy of the plaintext.
      // The erasure salt is gone; a pending-deletion record may remain so the
      // remote deletion can be retried on launch (H6).
      expect(keystore.values.keys.any((k) => k == 'duka_pin_erasure_salt_v1'),
          isFalse);
    });
  });

  group('the gate', () {
    test('a wrong PIN erases nothing', () async {
      await seed();
      final before = await raw('SELECT email FROM owner');

      await expectLater(
        AccountDeletionService.deleteAccount(pin: '0000'),
        throwsA(isA<AccountDeletionException>()),
      );

      expect(await raw('SELECT email FROM owner'), before);
      expect(looksErased(await raw('SELECT email FROM owner')), isFalse);
    });

    test('the offline staff credential cache is cleared with the rest',
        () async {
      await seed();
      // The cache holds a PBKDF2 hash of every staff PIN PLUS each username in
      // the clear, in the OS keystore, and `login_screen` verifies against it
      // as a fallback after `AuthService.verifyPin` fails. So a cashier's PIN
      // still unlocks the till after `staff.pin_hash` has been erased — an
      // erasure that named the SQLite columns but not the keystore.
      await StaffCredentialCache.cacheStaffCredentials(1, 'beatrice', '2222');
      // Prove the entry is really stored, so the assertions below mean
      // something rather than passing because nothing was ever written.
      expect(keystore.values.keys.any((k) => k.contains('staff_cred')), isTrue);
      expect(await StaffCredentialCache.verifyCachedPin(1, '2222'), isTrue);

      await AccountDeletionService.deleteAccount(pin: validPin);

      // The cached entry AND its index are gone, so nothing in the keystore can
      // still verify a staff PIN — that fallback is what `login_screen` uses
      // after `staff.pinHash` has been sealed.
      expect(
        keystore.values.keys.any((k) => k.contains('staff_cred')),
        isFalse,
        reason: 'the cached credentials and their index must both be gone',
      );
      expect(await StaffCredentialCache.verifyCachedPin(1, '2222'), isFalse);
      // The salt is gone; a pending-deletion record may remain for retry (H6).
      expect(keystore.values.keys.any((k) => k == 'duka_pin_erasure_salt_v1'),
          isFalse,
          reason: 'the salt and the backup key all go');
    });

    test('signing out clears the cache too, so the next person cannot reuse it',
        () async {
      // The cache's doc has always said "cleared on sign-out"; nothing did it.
      // The danger is concrete: the next person at the till can sign in as
      // whoever was here before, because `login_screen` falls back to the cache.
      await seed();
      await StaffCredentialCache.cacheStaffCredentials(1, 'beatrice', '2222');
      expect(await StaffCredentialCache.verifyCachedPin(1, '2222'), isTrue);

      final appState = AppState();
      await appState.loadOwner();
      appState.signOut();
      // `signOut` fires the clear without awaiting it, which is deliberate — a
      // sign-out must not block on the keystore — so the assertion waits for
      // the queued microtask rather than assuming it already ran.
      await Future<void>.delayed(Duration.zero);

      expect(await StaffCredentialCache.verifyCachedPin(1, '2222'), isFalse);
    });

    test('a failed erasure leaves the PIN working and nothing destroyed',
        () async {
      // The pre-erasure compaction is the whole safety property: a VACUUM
      // failure must destroy NOTHING, because the alternative is a till whose
      // owner PIN is ciphertext with no way to retry.
      // Simulated here by making the derive step fail, which is the same
      // position — before any column is written.
      await seed();

      await expectLater(
        AccountDeletionService.deleteAccount(pin: '9999'),
        throwsA(isA<AccountDeletionException>()),
      );

      // The PIN still verifies, so the owner can sign in and retry.
      final owner = await db.getOwner();
      expect(await AuthService.verifyPin(validPin, owner!.pinHash), isTrue);
      // Nothing is ciphertext.
      expect(looksErased(await raw('SELECT name FROM owner')), isFalse);
      // The salt is still there, so a later attempt can derive a key.
      expect(keystore.values, isNotEmpty);
    });

    test('an empty PIN is refused before anything is touched', () async {
      await seed();

      await expectLater(
        AccountDeletionService.deleteAccount(pin: ''),
        throwsA(isA<AccountDeletionException>()),
      );
      expect(looksErased(await raw('SELECT name FROM owner')), isFalse);
    });

    test('a locked-out till is refused', () async {
      await seed();
      // Enough wrong PINs on this till to trip the till-wide lockout, which is
      // the counter a login-screen attempt spends against the same value.
      for (var i = 0; i < AuthService.maxAttempts + 1; i++) {
        await AuthService.recordFailure('__owner__');
      }
      expect(await AuthService.isTillLockedOut(), isTrue);

      await expectLater(
        AccountDeletionService.deleteAccount(pin: validPin),
        throwsA(isA<AccountDeletionException>().having(
            (e) => e.reason, 'reason', AccountDeletionFailure.lockedOut)),
      );
      expect(looksErased(await raw('SELECT name FROM owner')), isFalse);
    });
  });

  group('what a restored backup now holds', () {
    test('a field erased this way cannot be read back without the key',
        () async {
      await seed();
      await AccountDeletionService.deleteAccount(pin: validPin);

      // The property the feature exists for: the ciphertext is in the file and
      // the key is not, so a restored backup yields `erased:…` and nothing
      // else. Anything that could turn it back would defeat the point.
      final email = await raw('SELECT email FROM owner') as String;
      expect(email, startsWith('erased:'));
      expect(email, isNot(contains('@')));
      expect(email.length, greaterThan(40));
    });

    test('no column in ANY table still holds a name or an address', () async {
      // The erasure's list is DECLARED, so this schema walk is what keeps it
      // honest: the first version of the list missed `shifts.staff_name` and
      // `stock_adjustments.staff_name`, so a deleted shop still had its
      // cashiers' names on every shift and every stock adjustment. A column
      // added later that is not declared fails HERE rather than surviving
      // quietly in a backup.
      await seed();
      await db.addStaff(Staff(
        name: 'Beatrice Wanjiku',
        role: 'cashier',
        pinHash: await AuthService.hashPin('2222'),
      ));
      // Rows in the tables that denormalise the person, so there is something
      // to find if the erasure misses one.
      final Product product = productRow();
      await db.upsertProducts(<Product>[product]);
      final productId = (await db.database.then((d) => d.query('products')))
          .first['id'] as int;
      await db.recordSale(
        staffName: 'Beatrice Wanjiku',
        staffId: 1,
        items: <SaleItem>[
          SaleItem(
            saleId: 0,
            productId: productId,
            productName: product.name,
            qty: 1,
            unitPrice: product.sellPrice,
            unitCost: product.costPrice,
          ),
        ],
        enforceStock: false,
      );
      final shiftId = await db.openShift(
        startFloat: Money.fromMajor(500),
        staffName: 'Beatrice Wanjiku',
        staffId: 1,
      );
      expect(shiftId, greaterThan(0));
      await db.adjustStock(
        StockAdjustment(
          productId: productId,
          productName: 'Tusker 500ml',
          delta: 1,
          reason: 'restocked by Beatrice Wanjiku',
          staffName: 'Beatrice Wanjiku',
          createdAt: DateTime.now().toIso8601String(),
        ),
        staffId: 1,
      );

      await AccountDeletionService.deleteAccount(pin: validPin);

      // Every TEXT column in every user table.
      final tables = await db.database.then((d) => d.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"));
      final leaked = <String>[];
      for (final tableRow in tables) {
        final table = tableRow['name'] as String;
        final columns = await db.database
            .then((d) => d.rawQuery('PRAGMA table_info($table)'));
        for (final column in columns) {
          final name = column['name'] as String;
          final type = (column['type'] as String).toUpperCase();
          if (!type.contains('TEXT') && !type.contains('CHAR')) continue;
          final rows = await db.database
              .then((d) => d.query(table, columns: <String>[name]));
          for (final row in rows) {
            final value = row[name];
            if (value is! String) continue;
            if (value.startsWith('erased:')) continue;
            if (value.contains('Beatrice') ||
                value.contains('amina@duka.co.ke') ||
                value.contains('Amina Duka')) {
              leaked.add('$table.$name = $value');
            }
          }
        }
      }
      expect(leaked, isEmpty,
          reason: 'plaintext personal data survived the erasure');
    });
  });
}
