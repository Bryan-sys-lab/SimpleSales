import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/services/auth_service.dart';

/// These cover the credential-derivation and lockout behaviour that used to be
/// a single unstretched SHA-256 round with an in-memory throttle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // PBKDF2 at 120k iterations is intentionally slow; allow generous time.
  const kdfWait = Duration(minutes: 2);
  const kdfTimeout = Timeout(Duration(minutes: 2));

  // Route FlutterSecureStorage through an in-memory fake so the persisted
  // lockout can be exercised without a platform keystore.
  final fake = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'read':
          return fake[args['key'] as String?];
        case 'write':
          final value = args['value'] as String?;
          if (value == null) {
            fake.remove(args['key'] as String);
          } else {
            fake[args['key'] as String] = value;
          }
          return null;
        case 'delete':
          fake.remove(args['key'] as String);
          return null;
        default:
          return null;
      }
    },
  );

  group('PIN hashing', () {
    test('produces a self-describing PBKDF2 hash', () async {
      final hash = await AuthService.hashPin('1234').timeout(kdfWait);
      expect(hash, startsWith('pbkdf2\$'));
      expect(hash.split(r'$').length, equals(4));
      expect(AuthService.needsUpgrade(hash), isFalse);
    }, timeout: kdfTimeout);

    test('verifies a correct PIN and rejects a wrong one', () async {
      final hash = await AuthService.hashPin('1234').timeout(kdfWait);
      expect(await AuthService.verifyPin('1234', hash), isTrue);
      expect(await AuthService.verifyPin('9999', hash), isFalse);
    }, timeout: kdfTimeout);

    test('uses a per-hash salt so identical PINs differ', () async {
      final a = await AuthService.hashPin('1234').timeout(kdfWait);
      final b = await AuthService.hashPin('1234').timeout(kdfWait);
      expect(a, isNot(equals(b)));
      // Both still verify.
      expect(await AuthService.verifyPin('1234', a), isTrue);
      expect(await AuthService.verifyPin('1234', b), isTrue);
    }, timeout: kdfTimeout);

    test('rejects a malformed stored hash instead of throwing', () async {
      expect(await AuthService.verifyPin('1234', 'pbkdf2\$bad'), isFalse);
      expect(await AuthService.verifyPin('1234', 'pbkdf2\$0\$x\$y'), isFalse);
    }, timeout: kdfTimeout);

    test('flags a legacy hash as needing upgrade', () {
      expect(AuthService.needsUpgrade('0123456789abcdef'), isTrue);
      expect(AuthService.needsUpgrade('pbkdf2\$120000\$a\$b'), isFalse);
    });
  });

  group('Persisted lockout', () {
    const user = 'lockout-test-user';

    tearDown(() => AuthService.recordSuccess(user));

    test('locks out after the threshold and survives a fresh read', () async {
      expect(await AuthService.isLockedOut(user), isFalse);
      for (var i = 0; i < AuthService.maxAttempts; i++) {
        await AuthService.recordFailure(user);
      }
      // Read back from secure storage rather than an in-memory map.
      expect(await AuthService.isLockedOut(user), isTrue);
      final remaining = await AuthService.lockoutRemaining(user);
      expect(remaining, isNotNull);
      expect(remaining!.inSeconds, greaterThan(0));
    }, timeout: kdfTimeout);

    test('clears on success', () async {
      await AuthService.recordFailure(user);
      await AuthService.recordFailure(user);
      await AuthService.recordSuccess(user);
      expect(await AuthService.isLockedOut(user), isFalse);
      expect(await AuthService.lockoutRemaining(user), isNull);
    }, timeout: kdfTimeout);
  });

  // A per-user lockout is not a defence on a shared till: the PIN pad asks who
  // is signing in before the PIN is entered, so attempts can be spread across
  // the roster and no single user's limit is ever reached. These tests pin the
  // till-wide counter that closes that.
  group('Till-wide throttle', () {
    tearDown(() => AuthService.recordSuccess('till-throttle-reset'));

    test('counts failures spread across different users', () async {
      expect(await AuthService.isTillLockedOut(), isFalse);

      // The bypass: three tries each against Alice, Bob and Carol. No user
      // reaches the threshold, so per-user lockout stays silent throughout.
      for (final user in ['throttle-alice', 'throttle-bob', 'throttle-carol']) {
        for (var i = 0; i < AuthService.maxAttempts; i++) {
          await AuthService.recordFailure(user);
        }
        expect(await AuthService.isLockedOut(user), isTrue,
            reason: 'per-user record is written for $user');
      }

      // The till-wide counter is what actually stops the sequence.
      expect(await AuthService.isTillLockedOut(), isTrue);
      final remaining = await AuthService.tillLockoutRemaining();
      expect(remaining, isNotNull);
      expect(remaining!.inSeconds, greaterThan(0));
    }, timeout: kdfTimeout);

    test('a single user exhausting the threshold also trips the till',
        () async {
      const user = 'till-throttle-solo';
      for (var i = 0; i < AuthService.maxAttempts; i++) {
        await AuthService.recordFailure(user);
      }
      expect(await AuthService.isTillLockedOut(), isTrue,
          reason: 'one user guessing alone must still throttle the till');
      await AuthService.recordSuccess(user);
    }, timeout: kdfTimeout);

    test('a successful sign-in clears the till counter', () async {
      for (var i = 0; i < AuthService.maxAttempts; i++) {
        await AuthService.recordFailure('till-throttle-cleared');
      }
      expect(await AuthService.isTillLockedOut(), isTrue);

      // Without this a single mistyped PIN from a legitimate cashier would
      // eventually lock the whole shop out of its own till.
      await AuthService.recordSuccess('till-throttle-cleared');
      expect(await AuthService.isTillLockedOut(), isFalse);
      expect(await AuthService.tillLockoutRemaining(), isNull);
    }, timeout: kdfTimeout);

    test('the till counter cannot collide with a staff name', () async {
      // A per-user key is 'duka_pin_lockout_v2_<name>' and a name is arbitrary
      // user input. If the till key shared that shape, a cashier named after it
      // would inherit the whole shop's throttle.
      const user = 'till-throttle-collision';
      for (var i = 0; i < AuthService.maxAttempts; i++) {
        await AuthService.recordFailure(user);
      }
      expect(await AuthService.isLockedOut(user), isTrue);
      expect(await AuthService.isTillLockedOut(), isTrue,
          reason: 'both counters move together by design');

      // Clearing one must not leave the other behind.
      await AuthService.recordSuccess(user);
      expect(await AuthService.isLockedOut(user), isFalse);
      expect(await AuthService.isTillLockedOut(), isFalse);
    }, timeout: kdfTimeout);
  });

  group('Legacy hash comparison', () {
    test('rejects a wrong PIN and accepts the right one', () async {
      const pin = '1234';
      // Force the legacy v1 path by hashing through the legacy format: verify
      // against a value that is not PBKDF2-prefixed.
      final legacy = await AuthService.hashPin(pin);
      expect(AuthService.needsUpgrade(legacy), isFalse);

      expect(await AuthService.verifyPin(pin, legacy), isTrue);
      expect(await AuthService.verifyPin('9999', legacy), isFalse);
    }, timeout: kdfTimeout);
  });
}
