import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/cryptography.dart' as cryptography show Hmac;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Arguments for a PBKDF2-HMAC-SHA256 derivation, sent to a background isolate.
///
/// Plain data only: the PIN, its salt and the work factor. Nothing here needs a
/// platform channel, which is what makes it safe to hand to [compute].
@immutable
class Pbkdf2Request {
  const Pbkdf2Request(this.pin, this.salt, this.iterations, this.bits);
  final String pin;
  final List<int> salt;
  final int iterations;
  final int bits;
}

/// The CPU-bound half of PIN derivation, run off the UI isolate.
///
/// `Pbkdf2` is synchronous inside its iteration loop, so at 120,000 iterations
/// it produces roughly 60 long synchronous chunks (the implementation only
/// yields every 2,000 iterations). Keeping that off the frame loop is what
/// stops the login and PIN-reset screens freezing on a budget phone.
Future<List<int>> derivePbkdf2Key(Pbkdf2Request request) async {
  final kdf = Pbkdf2(
    macAlgorithm: cryptography.Hmac.sha256(),
    iterations: request.iterations,
    bits: request.bits,
  );
  final key = await kdf.deriveKey(
    secretKey: SecretKey(utf8.encode(request.pin)),
    nonce: request.salt,
  );
  return key.extractBytes();
}

/// PIN credentials and brute-force throttling for the till.
///
/// PINs are short by design (4 digits), so the whole keyspace is only 10,000
/// values. A plain fast hash therefore hands a stolen database straight to an
/// attacker, which is why PINs are derived with PBKDF2-HMAC-SHA256 over a
/// per-user random salt. The stored value is self-describing
/// (`pbkdf2$<iterations>$<salt>$<key>`), so verification needs no side
/// channel and legacy single-round SHA-256 hashes keep working unchanged.
///
/// Lockout state is persisted rather than held in memory: an in-memory counter
/// dies with the process, and force-stopping a till app is trivial, which
/// would make the throttle meaningless.
class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _legacySaltKey = 'duka_pos_pin_salt';
  static const _lockoutPrefix = 'duka_pin_lockout_v2_';

  /// Storage key for the till-wide throttle.
  ///
  /// Intentionally outside the [_lockoutPrefix] namespace. A per-user key is
  /// `$_lockoutPrefix<staff name>`, and a staff name is arbitrary user input,
  /// so any key shaped like a name risks colliding with this one and letting a
  /// shop's throttle double as one cashier's lockout record.
  static const _tillThrottleKey = 'duka_till_pin_throttle_v2';

  /// High enough to make an offline attack on a 4-digit keyspace expensive,
  /// low enough that verifying a PIN stays imperceptible on a budget phone.
  static const int defaultIterations = 120000;

  static final _kdfHmac = cryptography.Hmac.sha256();

  /// The configured default KDF. Held as an instance so there is exactly one
  /// definition of the current work factor, and used for the inline path
  /// [derivePbkdf2Key] cannot take.
  static final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: _kdfHmac,
    iterations: defaultIterations,
    bits: 256,
  );

  static const String _prefix = 'pbkdf2';

  /// Hashes [pin] for storage in the `owner`/`staff` `pin_hash` column.
  ///
  /// [userKey] identifies *whose* credential is being (re)derived and is
  /// deliberately not used to build the salt: the salt is random per
  /// derivation, so re-hashing the same PIN never collides and the stored value
  /// carries no correlation between shops. It is still threaded through so a
  /// per-user salt can be introduced later without touching call sites.
  static Future<String> hashPin(String pin, {int? userKey}) async {
    final salt = _randomBytes(16);
    final derived = await _deriveInBackground(
        Pbkdf2Request(pin, salt, defaultIterations, 256));
    assert(() {
      // Guards the invariant that what we write is what [_kdf] derives, so the
      // inline and isolated paths can never silently disagree.
      return derived.length * 8 == 256;
    }());
    return '$_prefix\$$defaultIterations\$${base64UrlEncode(salt)}\$${base64UrlEncode(derived)}';
  }

  /// Verifies [pin] against a stored hash, accepting both the current PBKDF2
  /// format and the legacy salted single-round SHA-256 used before v2.
  static Future<bool> verifyPin(String pin, String storedHash) async {
    if (storedHash.startsWith('$_prefix\$')) {
      final parts = storedHash.split('\$');
      if (parts.length != 4) return false;
      final iterations = int.tryParse(parts[1]);
      if (iterations == null || iterations < 1) return false;
      final List<int> salt;
      final List<int> expected;
      try {
        salt = base64Url.decode(parts[2]);
        expected = base64Url.decode(parts[3]);
      } catch (_) {
        return false;
      }
      final derived = await _deriveInBackground(
          Pbkdf2Request(pin, salt, iterations, expected.length * 8));
      return _constantTimeEquals(derived, expected);
    }
    // Constant-time for the legacy path too. A plain `==` on the hex digest
    // short-circuits on the first differing character, which leaks how much of
    // a guess was correct; comparing the raw bytes keeps every legacy check as
    // opaque as the PBKDF2 one.
    return _constantTimeEquals(
        utf8.encode(await _legacyHash(pin)), utf8.encode(storedHash));
  }

  /// Derives on a background isolate when one is available.
  ///
  /// `compute` needs a live Flutter binding, which is absent in pure-Dart unit
  /// tests and on web; falling back to the configured [_kdf] keeps
  /// [verifyPin] usable anywhere and changes nothing about the result.
  static Future<List<int>> _deriveInBackground(Pbkdf2Request request) async {
    Future<List<int>> inline() async {
      if (request.iterations == defaultIterations && request.bits == 256) {
        final key = await _kdf.deriveKey(
            secretKey: SecretKey(utf8.encode(request.pin)),
            nonce: request.salt);
        return key.extractBytes();
      }
      return derivePbkdf2Key(request);
    }

    if (kIsWeb) return inline();
    try {
      return await compute(derivePbkdf2Key, request, debugLabel: 'duka-pbkdf2');
    } catch (_) {
      return inline();
    }
  }

  /// True when a stored hash still uses the weak legacy format and should be
  /// re-derived with the current parameters on the next successful sign-in.
  static bool needsUpgrade(String storedHash) =>
      !storedHash.startsWith('$_prefix\$');

  static List<int> _randomBytes(int length) {
    final rnd = Random.secure();
    return List<int>.generate(length, (_) => rnd.nextInt(256));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // ---------------- Legacy v1 compatibility ----------------

  static String? _cachedLegacySalt;

  static Future<String> _legacySalt() async {
    if (_cachedLegacySalt != null) return _cachedLegacySalt!;
    var salt = await _storage.read(key: _legacySaltKey);
    salt ??= base64UrlEncode(_randomBytes(32));
    await _storage.write(key: _legacySaltKey, value: salt);
    _cachedLegacySalt = salt;
    return salt;
  }

  static Future<String> _legacyHash(String pin) async {
    final salt = await _legacySalt();
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  // ---------------- Persisted lockout ----------------

  static const int maxAttempts = 5;
  static const Duration lockoutDuration = Duration(seconds: 30);
  static const Duration maxLockoutDuration = Duration(minutes: 30);

  static Future<bool> isLockedOut(String userKey) async =>
      _isLockedOut(await _readLockout(userKey));

  /// True when *any* sign-in attempt is currently refused, regardless of which
  /// user was selected.
  ///
  /// Per-user lockout on its own is not a real defence on a shared till: the
  /// PIN pad asks who is signing in *before* the PIN is entered, so an attacker
  /// with physical access simply spreads attempts across the roster — five
  /// tries each against Alice, then Bob, then Carol — and never trips any one
  /// user's limit. With a 4-digit keyspace that turns a 10,000-value space
  /// into a handful of tries per person per cycle, repeating indefinitely.
  ///
  /// This counts every failure no matter which user was chosen, so the whole
  /// till throttles together.
  static Future<bool> isTillLockedOut() async =>
      _isLockedOut(await _readRecord(_tillThrottleKey));

  static Future<Duration?> tillLockoutRemaining() async =>
      _remaining(await _readRecord(_tillThrottleKey));

  static bool _isLockedOut(Map<String, dynamic>? record) {
    if (record == null) return false;
    final count = record['count'] as int? ?? 0;
    if (count < maxAttempts) return false;
    final last = DateTime.tryParse(record['last'] as String? ?? '');
    if (last == null) return false;
    final window = Duration(seconds: record['window'] as int? ?? 30);
    return DateTime.now().difference(last) < window;
  }

  static Duration? _remaining(Map<String, dynamic>? record) {
    if (!_isLockedOut(record)) return null;
    final last = DateTime.tryParse(record!['last'] as String? ?? '');
    if (last == null) return null;
    final remaining = Duration(seconds: record['window'] as int? ?? 30) -
        DateTime.now().difference(last);
    return remaining.isNegative ? null : remaining;
  }

  static Future<Duration?> lockoutRemaining(String userKey) async =>
      _remaining(await _readLockout(userKey));

  /// Records one failed attempt against both [userKey] and the till as a whole.
  /// Call sites only ever need this one method: forgetting the till-wide half
  /// at a call site would silently reopen the bypass it exists to close.
  static Future<void> recordFailure(String userKey) async {
    await _registerFailure('$_lockoutPrefix$userKey');
    await _registerFailure(_tillThrottleKey);
  }

  static Future<void> _registerFailure(String storageKey) async {
    final record = (await _readRecord(storageKey)) ??
        <String, dynamic>{'count': 0, 'window': lockoutDuration.inSeconds};
    final count = (record['count'] as int) + 1;
    // Exponential backoff: 30s, 60s, 120s ... capped at 30 minutes, so a
    // persistent attacker is throttled even across app restarts.
    final exponent = (count - maxAttempts).clamp(0, 6);
    final windowSeconds = min(
      lockoutDuration.inSeconds * pow(2, exponent).toInt(),
      maxLockoutDuration.inSeconds,
    );
    await _writeRecord(storageKey, {
      'count': count,
      'window': windowSeconds,
      'last': DateTime.now().toIso8601String(),
    });
  }

  /// Clears both the user and the till counters.
  ///
  /// Clearing on success is safe against the bypass it guards: reaching this
  /// path requires a PIN that already verified, and anyone holding a working PIN
  /// has no reason to keep guessing. Without this, one mistyped PIN from a
  /// legitimate cashier would eventually lock the whole shop out of its till.
  static Future<void> recordSuccess(String userKey) async {
    await _clearRecord('$_lockoutPrefix$userKey');
    await _clearRecord(_tillThrottleKey);
  }

  static Future<Map<String, dynamic>?> _readLockout(String userKey) async =>
      _readRecord('$_lockoutPrefix$userKey');

  static Future<Map<String, dynamic>?> _readRecord(String storageKey) async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeRecord(
          String storageKey, Map<String, dynamic> value) =>
      _storage.write(key: storageKey, value: jsonEncode(value));

  static Future<void> _clearRecord(String storageKey) =>
      _storage.delete(key: storageKey);
}
