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

  /// The keys this cache has written, so it can be emptied without enumerating
  /// the keystore.
  ///
  /// `readAll` is the natural way to find owned keys, and it is not implemented
  /// on every platform (it throws `MissingPluginException` under test). Keeping
  /// an index means `clearAll` deletes exactly what this cache wrote, works
  /// everywhere, and never has to guess at other apps' storage.
  static const _indexKey = '${_prefix}index';

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
    final key = '$_prefix$staffId';
    await _storage.write(key: key, value: payload);
    await _index(staffId);
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

  /// Records [staffId] in the index, without duplicates.
  static Future<void> _index(int staffId) async {
    try {
      final raw = await _storage.read(key: _indexKey);
      final ids = raw == null || raw.isEmpty
          ? <String>{}
          : raw.split(',').where((s) => s.isNotEmpty).toSet();
      if (ids.add('$staffId')) {
        await _storage.write(key: _indexKey, value: ids.join(','));
      }
    } catch (_) {
      // The index is a convenience, not a credential. Failing to record it only
      // means `clearAll` may miss this entry — and `clearStaffCredentials`
      // still clears it directly, so it is never left behind on the paths that
      // matter (staff removal, account deletion).
    }
  }

  static Future<void> clearStaffCredentials(int staffId) async {
    await _storage.delete(key: '$_prefix$staffId');
  }

  static Future<void> clearAll() async {
    try {
      final raw = await _storage.read(key: _indexKey);
      final ids = raw == null || raw.isEmpty
          ? const <String>[]
          : raw.split(',').where((s) => s.isNotEmpty);
      for (final id in ids) {
        await _storage.delete(key: '$_prefix$id');
      }
      await _storage.delete(key: _indexKey);
    } catch (_) {
      // Swallowed, because this is called from `signOut`, and a sign-out that
      // threw would leave a caller holding a half-ended session — or, under
      // `unawaited`, an unhandled async error that takes the app down.
      //
      // Leaving stale cached credentials on a keystore refusal is not good, but
      // it is strictly better than the till refusing to sign anyone out.
    }
  }

  static List<int> _randomBytes(int length) {
    final rnd = Random.secure();
    return List<int>.generate(length, (_) => rnd.nextInt(256));
  }
}
