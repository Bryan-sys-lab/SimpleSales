import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_service.dart';

/// Offline credential cache for staff sign-in.
///
/// When the backend is unreachable, the till still has to let a known staff
/// member sign in. This cache stores a hashed version of the staff's PIN
/// keyed by their username, so the till can verify the PIN locally without
/// hitting the network.
///
/// The cache is populated on successful backend authentication and cleared
/// on sign-out. It is never the source of truth; it is only a fallback.
class StaffCredentialCache {
  static const _storage = FlutterSecureStorage();
  static const _prefix = 'duka_staff_cred_';

  static Future<void> cacheStaffCredentials(
      int staffId, String username, String pin) async {
    final salt = _randomBytes(16);
    final hash = await AuthService.hashPin(pin);
    final payload = jsonEncode(<String, dynamic>{
      'staffId': staffId,
      'username': username,
      'hash': hash,
      'salt': base64Url.encode(salt),
    });
    await _storage.write(key: '$_prefix$staffId', value: payload);
  }

  static Future<bool> verifyCachedPin(int staffId, String pin) async {
    final raw = await _storage.read(key: '$_prefix$staffId');
    if (raw == null) return false;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final expected = data['hash'] as String;
      return await AuthService.verifyPin(pin, expected);
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearStaffCredentials(int staffId) async {
    await _storage.delete(key: '$_prefix$staffId');
  }

  static Future<void> clearAll() async {
    final keys = await _storage.readAll();
    for (final key in keys.keys) {
      if (key.startsWith(_prefix)) {
        await _storage.delete(key: key);
      }
    }
  }

  static List<int> _randomBytes(int length) {
    final rnd = Random.secure();
    return List<int>.generate(length, (_) => rnd.nextInt(256));
  }
}
