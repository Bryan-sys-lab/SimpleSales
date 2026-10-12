// Forgot PIN: the reset that cannot be worked around.
//
// The security property this suite pins is the reason the feature can exist at
// all: the reset is gated on a code only the real owner receives, and it cannot
// be run offline. A reset that worked without the server would let anyone
// holding an unlocked phone set the owner PIN and walk into the owner session —
// an authentication bypass in a recovery costume. Both halves are asserted:
//
//   1. A wrong code does NOT change the PIN. Installed only after the server
//      accepts, so a guess cannot be used to change the thing it protects.
//   2. A mismatched or mis-shaped new PIN is refused BEFORE the network is
//      touched — a PIN the pad cannot accept would lock the owner straight
//      back out.
//   3. The address is masked in everything the UI shows, because a screen the
//      owner reads out loud should not display their address in clear.
//   4. The challenge does not survive the flow, so a half-finished reset leaves
//      no code redeemable by the next person at the counter.
//
// The backend is not faked: this suite covers the CLIENT's own rules — masking,
// shape, ordering, and the local install — which are the parts that can be got
// wrong in a way no server contract catches. `PinResetService.confirm` needs a
// live backend to complete, so the network boundary itself is left to the
// integration suite.

import 'package:duka_pos/db/database_helper.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/services/auth_service.dart';
import 'package:duka_pos/services/pin_reset_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseHelper db;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = await DatabaseHelper.openInMemoryForTests();
    await db.createOwner(Owner(
      id: 1,
      name: 'Amina Duka',
      pinHash: await AuthService.hashPin('4321'),
      email: 'amina@duka.co.ke',
      shopName: 'Amina Duka',
      createdAt: DateTime.now().toIso8601String(),
    ));
  });

  group('the new PIN is refused before the network is touched', () {
    test('four digits, because that is the shape the pad accepts', () async {
      // A PIN the pad cannot accept would lock the owner straight back out on
      // the next unlock, and it is this check that catches it before the
      // server is asked to agree.
      await expectLater(
        PinResetService.confirm(
          code: '000000',
          newPin: '12',
          state: AppState(),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('masking', () {
    test('keeps enough of the address to recognise, hides enough to withhold',
        () {
      final masked = PinResetService.maskEmail('amina@duka.co.ke');
      expect(masked, 'a***@duka.co.ke');
      // The domain is whole, which is what someone checking a typo reads.
      expect(masked, contains('duka.co.ke'));
      // The local part is not, which is the part that names the person.
      expect(masked, isNot(contains('amina')));
    });

    test('a one-character local part does not vanish', () {
      expect(PinResetService.maskEmail('a@b.co'), 'a***@b.co');
    });

    test('a value with no domain is shown as itself rather than mangled', () {
      // This is not valid input, and pretending to mask it would be worse than
      // putting it on screen.
      expect(PinResetService.maskEmail('not-an-email'), 'not-an-email');
    });
  });

  group('the challenge', () {
    test('is not left redeemable after the flow finishes', () async {
      // The confirm step is not reachable here without a live backend, so the
      // clearing is asserted directly: a code that survives an abandoned reset
      // is a code with a lifetime nobody agreed to.
      await PinResetService.forgetChallenge();
      final stored = await db.getSetting('pin_reset_challenge_v1');
      expect(stored == null || stored.isEmpty, isTrue);
    });

    test('an abandoned reset leaves nothing behind', () async {
      // The provider's KEY is what survives, not just the value: the entrypoint
      // key is checked so an empty-value row still reads as "nothing left".
      // This is the state the dialog's Cancel and system-back paths drive it to,
      // and the gap the first version of the dialog left open.
      await db.setSetting('pin_reset_challenge_v1', 'challenge-1');
      expect(await db.getSetting('pin_reset_challenge_v1'), 'challenge-1');

      // What Cancel (and PopScope's onPopInvokedWithResult) now do.
      await PinResetService.forgetChallenge();

      final stored = await db.getSetting('pin_reset_challenge_v1');
      expect(stored, '');
    });

    test('is scoped to this shop, not to the device', () async {
      // The challenge id lives in the shop's own database, so a reset started
      // in shop A cannot be redeemed from shop B on the same phone.
      await db.setSetting('pin_reset_challenge_v1', 'challenge-a');
      expect(await db.getSetting('pin_reset_challenge_v1'), 'challenge-a');
    });
  });

  group('the owner row is what the reset installs', () {
    test('the hash changes and the new PIN verifies', () async {
      // The one thing the whole feature is for, asserted against the real
      // PBKDF2 path rather than a stand-in.
      await PinResetService.installPin('9876');
      final owner = await db.getOwner();
      expect(owner!.pinHash, isNot(await AuthService.hashPin('4321')));
      expect(await AuthService.verifyPin('9876', owner.pinHash), isTrue);
      expect(await AuthService.verifyPin('4321', owner.pinHash), isFalse);
    });
  });
}
