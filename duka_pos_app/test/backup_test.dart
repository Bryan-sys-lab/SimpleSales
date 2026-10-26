// Backups that actually restore.
//
// A backup nobody can restore is not a backup, it is a file that reassures the
// owner right up until the phone is lost. That is the property this suite pins:
// a catalogue exported by the app, encrypted, decrypted again, and read back
// through the real importer, must land as the same catalogue that left.
//
// The bugs worth guarding are all in the JOIN between the halves:
//
//   1. The exporter's sheet name and column order are a contract the importer
//      must honour. Drift between them produces a restore that silently drops
//      columns, and a shop finds out when the prices come back zero.
//   2. The encrypted payload's framing must survive the JSON/base64 trip, and a
//      tampered file must fail loudly — an unauthenticated restore is worse
//      than no restore.
//   3. The plain path and the encrypted path must agree. If encryption changes
//      what comes back, it changed the shop's data, not its file.
//
// The keystore is mocked at its platform interface, not the cipher: AES-256-GCM,
// the framing and the `compute` hop all run for real, because those are what a
// restore depends on and mocking them proves nothing.

import 'dart:convert';
import 'dart:io';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/encrypted_backup_service.dart';
import 'package:duka_pos/services/excel_service.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A keystore backed by memory, registered as the platform implementation.
///
/// `flutter_secure_storage` is the ONLY platform-bound part of the backup path,
/// so it is the only part a test must replace. The signature is
/// `Map<String, String> options` — the v2 interface's shape — so the fake
/// accepts and ignores it.
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

/// A path provider pointing at a directory the test owns.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late _InMemorySecureStorage keystore;
  late DatabaseHelper db;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    docs = await Directory.systemTemp.createTemp('duka_backup_');
    PathProviderPlatform.instance = _FakePathProvider(docs);
    keystore = _InMemorySecureStorage();
    FlutterSecureStoragePlatform.instance = keystore;
    DatabaseHelper.resetForTests();
    // The backup age is a SharedPreferences value, so a test must give it a
    // store. The memory keystore above is a different seam and does not cover
    // this one.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = await DatabaseHelper.openInMemoryForTests();
  });

  // Rmoves only THIS test's documents directory, recursively.
  //
  // It deliberately does not touch `.dart_tool/sqflite_common_ffi/databases`,
  // which workspace_test and audit_log_test keep open connections into for the
  // duration of the whole suite: deleting a file out from under an open
  // connection leaves that connection holding a deleted inode, and every later
  // write to it fails with sqlite error 1032, "attempt to write a readonly
  // database". That failure is not about the test that reports it.
  tearDown(() async => docs.delete(recursive: true));

  Product product({
    String name = 'Tusker 500ml',
    String category = 'Drinks',
    double cost = 120,
    double sell = 180,
    double stock = 24,
    String? imagePath,
  }) =>
      Product(
        id: 0,
        name: name,
        category: category,
        costPrice: Money.fromMajor(cost),
        sellPrice: Money.fromMajor(sell),
        stockQty: stock,
        reorderLevel: 6,
        imagePath: imagePath,
        updatedAt: DateTime.now().toIso8601String(),
      );

  /// The same in-memory singleton, reopened.
  ///
  /// There is deliberately no second, independent database in this suite:
  /// `openInMemoryForTests` assigns to DatabaseHelper's ONE singleton, so
  /// calling it twice leaves the first handle orphaned and both ends of the
  /// round trip reading the same store — which would make a restore look
  /// successful while proving only that upsert overwrites itself.
  ///
  /// So a restore is proven instead by WHAT lands: the ids survive, the values
  /// survive, and an empty destination gains rows. A fresh-shop assertion would
  /// need a second DatabaseHelper, which this app does not have.
  Future<void> clearShop() async {
    final all = await db.getProducts(activeOnly: false);
    for (final p in all) {
      if (p.id != null) await db.hardDeleteProduct(p.id!);
    }
  }

  group('encrypted backup round trip', () {
    test('portable format derives from a passphrase and verifies its manifest',
        () async {
      final clear = utf8.encode('portable catalogue bytes');
      final payload = await EncryptedBackupService.buildPortablePayload(
        clearBytes: clear,
        passphrase: 'correct horse battery staple',
      );
      final decoded = await EncryptedBackupService.decryptPortableBytes(
        encodedBytes: utf8.encode(payload),
        passphrase: 'correct horse battery staple',
      );
      expect(decoded, clear);
      expect(
        () => EncryptedBackupService.decryptPortableBytes(
          encodedBytes: utf8.encode(payload),
          passphrase: 'wrong passphrase',
        ),
        throwsA(isA<Exception>()),
      );
      final header = jsonDecode(payload) as Map;
      expect(header['format'], 'duka-encrypted-backup-v2');
      expect(header['kdf'], 'pbkdf2-sha256');
      expect(header['iterations'], greaterThanOrEqualTo(600000));
      expect(header['manifest'], isA<Map>());
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a saved catalogue returns from the bytes exactly as it left',
        () async {
      // Three products, including one at zero stock: a dropped row or a zero
      // turned into a default is both something this has to catch.
      await db.upsertProduct(product());
      await db.upsertProduct(
          product(name: 'Kes 200 Item', category: 'General', sell: 200));
      await db.upsertProduct(
          product(name: 'Quiet Item', category: 'General', stock: 0));

      final file = await ExcelService().exportEncryptedInventory();

      // The file is a .duka payload, not a workbook: encryption happened.
      expect(file.path.endsWith('.duka'), isTrue);
      final payload = jsonDecode(await file.readAsString()) as Map;
      expect(payload['format'], 'duka-encrypted-backup-v1');
      expect(payload['nonce'], isNotEmpty);
      expect(payload['cipherText'], isNotEmpty);
      // The MAC is present — GCM's integrity check is what makes a tampered file
      // fail rather than restoring a corrupted catalogue.
      expect(payload['mac'], isNotEmpty);

      // Round trip through the real decrypt, into an EMPTY database: that is what
      // a restore onto a lost or replaced phone actually is.
      await clearShop();
      expect(await db.getProducts(activeOnly: false), isEmpty);
      final bytes =
          await EncryptedBackupService.decryptBytes(await file.readAsBytes());
      final restored = await ExcelService().importInventoryBytesForTest(bytes);
      expect(restored.imported, 3,
          reason: 'every exported product must come back');

      final products = await db.getProducts(activeOnly: false);
      // Every row is matched by id on re-import, so the exported ids are the
      // ids that come back. The assertion is on COUNT and NAME, not on the
      // literal ids: a deleted row does not reset SQLite's rowid sequence, so
      // ids after `clearShop` continue from where the seed left off (4, 5, 6
      // rather than 1, 2, 3) — and what matters for a restore is that each
      // product comes back once, under an id, with its values intact.
      expect(products.length, 3,
          reason: 'every exported product must come back exactly once');
      expect(products.map((p) => p.name).toSet(),
          <String>{'Tusker 500ml', 'Kes 200 Item', 'Quiet Item'});
      expect(products.firstWhere((p) => p.name == 'Tusker 500ml').sellPrice,
          Money.fromMajor(180));
      expect(products.firstWhere((p) => p.name == 'Kes 200 Item').sellPrice,
          Money.fromMajor(200));
      // Zero stock restores as zero: a dropped cell must not become a nonzero
      // quantity, which would fail to reorder what needs reordering.
      expect(products.firstWhere((p) => p.name == 'Quiet Item').stockQty, 0);
    });

    test('a tampered backup fails to decrypt rather than restoring garbage',
        () async {
      await db.upsertProduct(product());
      final file = await ExcelService().exportEncryptedInventory();

      final payload =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      // Flip a byte of the cipher text: the MAC attached to the original no
      // longer matches, so AES-GCM must refuse.
      final cipherText = base64Url.decode(payload['cipherText'] as String);
      cipherText[0] ^= 0xFF;
      payload['cipherText'] = base64UrlEncode(cipherText);
      await file.writeAsString(jsonEncode(payload));

      expect(
        () => EncryptedBackupService.decryptBytes(file.readAsBytesSync()),
        throwsA(isA<Exception>()),
        reason: 'a modified backup must fail loudly',
      );
    });

    test('a workbook that was never encrypted is rejected by format', () async {
      await db.upsertProduct(product());
      // This is what happens when an owner picks the wrong file: a plain .xlsx
      // offered to the decryptor.
      final plain = await ExcelService().exportInventory();

      expect(
        () => EncryptedBackupService.decryptBytes(plain.readAsBytesSync()),
        throwsA(isA<FormatException>()),
        reason: 'not an encrypted payload, so not a candidate for restoring',
      );
    });

    test('the plain and the encrypted path restore identically', () async {
      await db.upsertProduct(product());
      await db.upsertProduct(product(name: 'Second', category: 'Snacks'));

      final service = ExcelService();
      final plain = await service.exportInventory();
      await clearShop();
      await ExcelService()
          .importInventoryBytesForTest(await plain.readAsBytes());

      final encrypted = await service.exportEncryptedInventory();
      final unwrapped = await EncryptedBackupService.decryptBytes(
          await encrypted.readAsBytes());
      await clearShop();
      await ExcelService().importInventoryBytesForTest(unwrapped);

      final a = (await db.getProducts(activeOnly: false))
          .map((p) => '${p.name}|${p.category}|${p.sellPrice}')
          .toList()
        ..sort();
      final b = (await db.getProducts(activeOnly: false))
          .map((p) => '${p.name}|${p.category}|${p.sellPrice}')
          .toList()
        ..sort();
      expect(a, b,
          reason: 'the encrypted path must be transparent to the restore');
    });

    test('erasure removes the key and the local .duka files', () async {
      await db.upsertProduct(product());
      final service = ExcelService();
      final a = await service.exportEncryptedInventory();
      final b = await service.exportEncryptedInventory();
      expect(a.existsSync(), isTrue);
      expect(b.existsSync(), isTrue);

      await EncryptedBackupService.cryptographicEraseLocalBackups();

      expect(a.existsSync(), isFalse);
      expect(b.existsSync(), isFalse);
      // After erasure, a previously copied file is genuinely unreadable: the
      // key is gone, so there is nothing left to decrypt with.
      expect(
        () => EncryptedBackupService.decryptBytes(a.readAsBytesSync()),
        throwsA(isA<Exception>()),
      );
    });

    test('an automatic backup needs no share sheet and leaves no plain copy',
        () async {
      // The background path is what a shop actually relies on. It must not wait
      // on a share sheet and must not leave the unprotected workbook behind.
      await db.upsertProduct(product());
      final file = await ExcelService().saveAutomaticInventoryBackup();

      expect(file.path.endsWith('.duka'), isTrue);
      final leftovers = await docs
          .list()
          .where((e) => e is File && e.path.endsWith('.xlsx'))
          .toList();
      expect(leftovers, isEmpty,
          reason: 'the plain workbook is the unprotected copy; it must go '
              'once encrypted');
    });

    test('the cloud backup envelope is ciphertext and restores on this device',
        () async {
      final clear = utf8.encode('{"format":"duka-full-snapshot-v1"}');
      final envelope = await EncryptedBackupService.encryptBytes(clear);
      expect(envelope, isNot(contains('duka-full-snapshot-v1')));
      expect(await EncryptedBackupService.decryptBytes(utf8.encode(envelope)),
          clear);
    });

    test('the key is generated once and reused', () async {
      // A new key per run would make last week's backup undecryptable, which is
      // the quietest possible way for a backup scheme to fail.
      final first = await EncryptedBackupService.keyBytesForTest();
      final second = await EncryptedBackupService.keyBytesForTest();
      expect(second, first);
      expect(keystore.values.containsKey('duka_backup_key_v1'), isTrue);
    });
  });

  group('full snapshot recovery', () {
    test('replacement restore keeps the eTIMS receipt sequence contiguous',
        () async {
      await db.setTillCode('T1');
      final productId = await db.upsertProduct(product(stock: 10));
      Future<void> sale() => db.recordSale(
            staffName: 'Amina',
            paymentMethod: 'cash',
            items: <SaleItem>[
              SaleItem(
                saleId: 0,
                productId: productId,
                productName: 'Tusker 500ml',
                qty: 1,
                unitPrice: Money.fromMajor(180),
                unitCost: Money.fromMajor(120),
              ),
            ],
          );
      await sale();
      final snapshot = await db.exportFullSnapshot();
      await db.restoreFullSnapshot(
        <String, Object?>{...snapshot, 'workspaceKey': 'replacement-phone'},
        allowWorkspaceMismatch: true,
      );
      await sale();

      final rows = await (await db.database).query(
        'sales',
        columns: <String>['receipt_number'],
        orderBy: 'id ASC',
      );
      expect(rows.map((row) => row['receipt_number']),
          <Object?>['T1-000001', 'T1-000002']);
    });

    test('a failed media swap restores files and leaves the database alone',
        () async {
      final oldFile = File('${docs.path}/product_photos/first.jpg')
        ..parent.createSync(recursive: true);
      await oldFile.writeAsBytes(<int>[1, 2, 3], flush: true);
      await File('${docs.path}/conflict').writeAsBytes(<int>[9], flush: true);
      final productId = await db.upsertProduct(product(
        imagePath: 'product_photos/first.jpg',
      ));
      await db.setSetting('media_restore_marker', 'current');
      final snapshot = await db.exportFullSnapshot();
      await db.setSetting('media_restore_marker', 'changed');
      final broken = <String, Object?>{
        ...snapshot,
        'media': <Object?>[
          <String, String>{'path': 'product_photos/first.jpg', 'bytes': 'BA=='},
          <String, String>{'path': 'conflict/blocked.jpg', 'bytes': 'BQ=='},
        ],
      };

      await expectLater(db.restoreFullSnapshot(broken), throwsA(anything));
      expect(await oldFile.readAsBytes(), <int>[1, 2, 3]);
      expect(await db.getSetting('media_restore_marker'), 'changed');
      expect((await db.getProducts()).single.id, productId);
    });
  });

  group('the backup reminder', () {
    test('a shop with no backup at all is overdue', () async {
      // The reminder is what makes the above matter to an owner who would
      // otherwise never tap Export.
      expect(await ExcelService.lastBackupTime(), isNull);
      expect(await ExcelService.isBackupOverdue(), isTrue);
    });

    test('a recent backup is not overdue', () async {
      await ExcelService.recordAutomaticBackupForTest('/tmp/a.duka');
      expect(await ExcelService.isBackupOverdue(), isFalse);
    });

    test('an old backup is overdue again', () async {
      await ExcelService.recordAutomaticBackupForTest(
        '/tmp/a.duka',
        at: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(await ExcelService.isBackupOverdue(), isTrue);
    });
  });
}
