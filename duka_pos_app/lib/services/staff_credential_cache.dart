import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_service.dart';
import 'workspace_service.dart';

/// Offline credential cache for staff sign-in.
///
/// When the backend is unreachable, the till still has to let a known staff
/// member sign in. This cache stores a hashed version of the staff's PIN
/// keyed by their username, so the till can verify the PIN locally without
/// hitting the network.
///
/// The cache is populated on successful backend authentication and cleared
/// on sign-out. It is never the source of truth; it is only a fallback.
///
/// ## WHY THE KEY NAMES THE SHOP
///
/// Staff ids are PER SHOP. Shop A's cashier #1 and shop B's cashier #1 are
/// different people who happen to share a number, because each shop numbers
/// its own roster from one.
///
/// A key of the staff id alone therefore collided: the PIN cached for shop
/// A's cashier #1 was found again for shop B's cashier #1, and a till that
/// could not reach the server accepted one shop's PIN in another shop. The
/// key names the shop as well as the person, so a PIN belongs to the shop it
/// was set in and to nobody else.
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

  /// The key for one staff member in one shop.
  ///
  /// The workspace key is part of it because staff ids are not unique across
  /// shops, and the workspace key is the part that says WHICH shop.
  static Future<String> _keyFor(int staffId) async {
    // The shop, when it can be read.
    //
    // It cannot always be: the preferences are a platform channel, and a
    // credential cache that REFUSES to store a PIN because a platform channel
    // is missing is a cache that never helps anybody. So the key falls back
    // to a single shop, and the cache is still a cache.
    String workspace = 'default';
    try {
      workspace = await WorkspaceService.activeWorkspaceKey();
    } catch (_) {
      // No preferences: the till has one shop as far as this can tell.
    }
    final String safe = workspace.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '$_prefix$safe#$staffId';
  }

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
    final key = await _keyFor(staffId);
    await _storage.write(key: key, value: payload);
    await _index(key);
  }

  static Future<bool> verifyCachedPin(int staffId, String pin) async {
    final key = await _keyFor(staffId);
    final raw = await _storage.read(key: key);
    if (raw == null) return false;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final expected = data['hash'] as String;
      return await AuthService.verifyPin(pin, expected);
    } catch (_) {
      return false;
    }
  }

  /// Records [key] in the index, without duplicates.
  static Future<void> _index(String key) async {
    try {
      final raw = await _storage.read(key: _indexKey);
      final keys = raw == null || raw.isEmpty
          ? <String>{}
          : raw.split('\n').where((s) => s.isNotEmpty).toSet();
      if (keys.add(key)) {
        await _storage.write(key: _indexKey, value: keys.join('\n'));
      }
    } catch (_) {
      // The index is a convenience, not a credential. Failing to record it only
      // means `clearAll` may miss this entry — and `clearStaffCredentials`
      // still clears it directly, so it is never left behind on the paths that
      // matter (staff removal, account deletion).
    }
  }

  static Future<void> clearStaffCredentials(int staffId) async {
    await _storage.delete(key: await _keyFor(staffId));
  }

  static Future<void> clearAll() async {
    try {
      final raw = await _storage.read(key: _indexKey);
      final keys = raw == null || raw.isEmpty
          ? const <String>[]
          : raw.split('\n').where((s) => s.isNotEmpty);
      for (final key in keys) {
        await _storage.delete(key: key);
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
