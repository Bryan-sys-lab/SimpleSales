import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// PINs are hashed with a salt that is random per install and stored in the
/// OS keystore (Android Keystore / iOS Keychain via flutter_secure_storage) —
/// never in source code, never in the SQLite database itself. This means a
/// copied database file alone (e.g. from an unencrypted backup someone else
/// gets hold of) is not enough to brute-force PINs, since the salt isn't in it.
///
/// Also tracks failed PIN attempts per user for lockout (see [recordFailure],
/// [isLockedOut]) — a shared shop till with a 4-digit PIN is guessable in
/// under 10,000 tries with no lockout; with a short lockout after 5 tries,
/// brute-forcing becomes impractical without anyone noticing.
class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _saltKey = 'duka_pos_pin_salt';
  static String? _cachedSalt;

  static Future<String> _getSalt() async {
    if (_cachedSalt != null) return _cachedSalt!;
    var salt = await _storage.read(key: _saltKey);
    if (salt == null) {
      salt = _generateSalt();
      await _storage.write(key: _saltKey, value: salt);
    }
    _cachedSalt = salt;
    return salt;
  }

  static String _generateSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static Future<String> hashPin(String pin) async {
    final salt = await _getSalt();
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  static Future<bool> verifyPin(String pin, String hash) async =>
      (await hashPin(pin)) == hash;

  // ---------------- Lockout tracking ----------------
  // Keyed by user name; kept in memory only (resets if the app is killed,
  // which is an acceptable tradeoff for a shop till — the goal is to slow
  // down a guessing attempt in the moment, not survive a full app restart).
  static final Map<String, _AttemptRecord> _attempts = {};
  static const int maxAttempts = 5;
  static const Duration lockoutDuration = Duration(seconds: 30);

  static bool isLockedOut(String userKey) {
    final rec = _attempts[userKey];
    if (rec == null) return false;
    if (rec.count < maxAttempts) return false;
    final elapsed = DateTime.now().difference(rec.lastAttempt);
    if (elapsed > lockoutDuration) {
      _attempts.remove(userKey);
      return false;
    }
    return true;
  }

  static Duration? lockoutRemaining(String userKey) {
    final rec = _attempts[userKey];
    if (rec == null || rec.count < maxAttempts) return null;
    final elapsed = DateTime.now().difference(rec.lastAttempt);
    final remaining = lockoutDuration - elapsed;
    return remaining.isNegative ? null : remaining;
  }

  static void recordFailure(String userKey) {
    final rec = _attempts.putIfAbsent(userKey, () => _AttemptRecord());
    rec.count++;
    rec.lastAttempt = DateTime.now();
  }

  static void recordSuccess(String userKey) {
    _attempts.remove(userKey);
  }
}

class _AttemptRecord {
  int count = 0;
  DateTime lastAttempt = DateTime.now();
}
