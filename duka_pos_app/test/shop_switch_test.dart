// Choosing a shop, and switching to one.
//
// ## WHAT WENT WRONG
//
// Two reports, one cause.
//
//  * "Switching to an already-created shop while logged into another shop
//    lands you into a blank app until you tap any nav icon."
//  * "While creating a new shop the app takes you to login and says there is
//    no account on this device, and when I quit and restart it goes back to
//    normal."
//
// The stage — and therefore the router — decides where the person is from ONE
// thing: whether anybody is signed in. The switch dropped the session FIRST
// and read the new shop SECOND, so there was a moment when the app believed
// nobody was signed in. The guard answered it by redirecting to the welcome
// screen, which unmounted the screen that was doing the switch — so the step
// that signs the new shop in never ran, and the step that creates the new
// shop's owner never ran either.
//
// The blank shell is the same defect seen a frame earlier: the shell's branch
// navigator was disposed and nothing asked for it again, so the body was
// empty until a nav icon did.
//
// ## WHAT IS PINNED
//
//   * A switch NEVER announces "signed out". The stage is watched for the
//     whole switch, and every notification must show a signed-in session.
//   * A switch leaves the person signed in to the shop they switched TO.
//   * A switch can create the new shop's owner, so a new shop is never left
//     empty.
//   * A chooser — the sign-in screen's shop picker — moves the app WITHOUT
//     signing anybody in, because the whole point of it is to go on to type a
//     PIN.
//
// ## A NOTE ON THE KEYS
//
// Every shop in this suite gets a key of its own, and no test uses the
// `legacy` key for an owner row: that key opens the SHARED `duka_pos.db`
// file, and a row left in it by an earlier case is a UNIQUE constraint
// failure that has nothing to do with the behaviour under test.

import 'dart:io';

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/workspace_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final Directory _ffiDatabases =
    Directory('.dart_tool/sqflite_common_ffi/databases');

/// A key no other case has used, so no two cases share a database file.
String _key(String name) =>
    'shop-$name-${DateTime.now().microsecondsSinceEpoch}';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    if (_ffiDatabases.existsSync()) {
      for (final FileSystemEntity file in _ffiDatabases.listSync()) {
        if (file is File && file.path.endsWith('.db')) {
          file.deleteSync();
        }
      }
    }
  });

  setUp(() async {
    DatabaseHelper.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'workspace_registry_v1': '{}',
    });
  });

  /// A shop with an owner in it, registered.
  Future<String> seedShop(String name) async {
    final String key = _key(name);
    await WorkspaceService.register(workspaceKey: key, shopName: name);
    await WorkspaceService.setActiveWorkspace(key);
    await DatabaseHelper.instance.initializeWorkspace(key);
    await DatabaseHelper.instance.createOwner(Owner(
      id: 1,
      name: '$name owner',
      pinHash: 'hash',
      email: 'owner@$key.test',
      shopName: name,
      createdAt: DateTime.now().toIso8601String(),
    ));
    return key;
  }

  group('switching to a shop that already exists', () {
    test('the person is signed in to the shop they switched TO', () async {
      final String first = await seedShop('Kariuki');
      await seedShop('Njeri');

      final AppState state = AppState();
      await state.loadOwner();
      state.signInAsOwner();
      expect(state.isSignedIn, isTrue);
      expect(state.owner?.shopName, 'Njeri');

      await state.switchWorkspace(first);

      expect(state.owner?.shopName, 'Kariuki');
      expect(state.currentStaffName, 'Kariuki owner');
      expect(state.isOwnerSession, isTrue);
      expect(state.isSignedIn, isTrue);
      expect(state.workspaceKey, first);
    });

    test('the switch never announces that nobody is signed in', () async {
      final String first = await seedShop('Kariuki');
      await seedShop('Njeri');

      final AppState state = AppState();
      await state.loadOwner();
      state.signInAsOwner();

      // Every notification is watched, and every one of them must show a
      // signed-in session. A single "signed out" in the middle of the switch
      // is the whole bug: the router acts on it and throws the person out.
      final List<bool> signedInWhenNotified = <bool>[];
      state.addListener(() => signedInWhenNotified.add(state.isSignedIn));

      await state.switchWorkspace(first);

      expect(signedInWhenNotified, isNotEmpty,
          reason: 'the switch has to say something — a silent switch is a '
              'screen that does not redraw');
      expect(
        signedInWhenNotified.every((bool signedIn) => signedIn),
        isTrue,
        reason: 'the app must never believe it is signed out while it is '
            'changing shops: $signedInWhenNotified',
      );
    });
  });

  group('switching to a shop that does not exist yet', () {
    test('the new shop gets its owner, and the person is signed in', () async {
      await seedShop('Kariuki');

      final AppState state = AppState();
      await state.loadOwner();

      final String key = _key('new');
      await WorkspaceService.register(workspaceKey: key, shopName: 'Mwirigi');

      await state.switchWorkspace(
        key,
        createOwnerFor: Owner(
          id: 1,
          name: 'Amina',
          pinHash: 'hash',
          email: 'amina@test.test',
          shopName: 'Mwirigi',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

      // The shop is not empty: the owner row is in the NEW shop's database.
      final Owner? written = await DatabaseHelper.instance.getOwner();
      expect(written, isNotNull);
      expect(written?.shopName, 'Mwirigi');
      expect(state.owner?.shopName, 'Mwirigi');
      expect(state.isSignedIn, isTrue);
    });
  });

  group('the chooser on the sign-in screen', () {
    test('it moves the app to the shop without signing anybody in', () async {
      await seedShop('Kariuki');
      final String second = await seedShop('Njeri');

      final AppState state = AppState();
      await state.loadOwner();
      state.signOut();

      await state.switchWorkspace(second, signIn: false);

      // The app is pointed at the other shop...
      expect(state.owner?.shopName, 'Njeri');
      // ...and nobody is signed in, because the person has not typed a PIN yet.
      expect(state.isSignedIn, isFalse);
      expect(state.currentStaffName, isNull);
    });
  });

  group('the shops on the device', () {
    test('every shop is listed', () async {
      final String a = await seedShop('Kariuki');
      final String b = await seedShop('Njeri');
      final String c = await seedShop('Amina');

      final List<LocalShop> shops = await WorkspaceServiceShops.localShops();
      expect(shops.length, 3);
      expect(
        shops.map((LocalShop s) => s.workspaceKey).toSet(),
        <String>{a, b, c},
      );
    });

    test('a device with one shop has nothing to choose', () async {
      await seedShop('Kariuki');
      final List<LocalShop> shops = await WorkspaceServiceShops.localShops();
      expect(shops.length, 1);
    });
  });
}
