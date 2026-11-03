import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/session_renewal.dart';

class IdentityService {
  static const _storage = FlutterSecureStorage();
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _expiryKey = 'token_expiry';
  static const _tierKey = 'token_tier';

  static const backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://your-backend/api',
  );

  static Future<bool> get isConfigured async => true;

  static Future<SessionRenewal>? _refreshing;

  static Future<String?> get accessToken async {
    final cached = await _cachedAccessToken();
    if (cached != null) return cached;
    final outcome = await renew();
    return outcome is SessionRenewed ? await _cachedAccessToken() : null;
  }

  static Future<String?> _cachedAccessToken() async {
    final token = await _storage.read(key: _accessTokenKey);
    final rawExpiry = await _storage.read(key: _expiryKey);
    final expiry = rawExpiry == null ? null : DateTime.tryParse(rawExpiry);
    if (token != null &&
        expiry != null &&
        expiry.isAfter(DateTime.now().add(const Duration(seconds: 60)))) {
      return token;
    }
    return null;
  }

  static Future<String?> get tokenTier async => _storage.read(key: _tierKey);

  static Future<bool> get isAuthenticated async => (await accessToken) != null;

  /// Stores the tokens returned by the verification flow.
  ///
  /// The verification endpoint issues the same kind of session a login does,
  /// but [BackendService] is the one that calls it. This keeps the storage
  /// logic in one place rather than duplicating it.
  static Future<void> storeVerificationTokens(Map<String, dynamic> data) async {
    final access = data['access_token'] as String?;
    final refresh = data['refresh_token'] as String?;
    final expiresIn = (data['expires_in_seconds'] as num?)?.toInt() ?? (12 * 3600);
    if (access == null) return;
    await _storeTokens(
      accessToken: access,
      refreshToken: refresh,
      expiry: DateTime.now().add(Duration(seconds: expiresIn)),
      tier: 'device',
    );
  }

  static Future<void> _storeTokens({
    required String? accessToken,
    required String? refreshToken,
    required DateTime? expiry,
    required String? tier,
  }) async {
    if (accessToken != null) await _storage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null) await _storage.write(key: _refreshTokenKey, value: refreshToken);
    if (expiry != null) await _storage.write(key: _expiryKey, value: expiry.toIso8601String());
    if (tier != null) await _storage.write(key: _tierKey, value: tier);
  }

  static Future<void> _clearStoredTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _expiryKey);
    await _storage.delete(key: _tierKey);
  }

  static Future<bool> isOnline() async {
    try {
      final client = http.Client();
      final resp = await client
          .get(Uri.parse('$backendUrl/health'))
          .timeout(const Duration(seconds: 3));
      client.close();
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> login(String email, String password) async {
    try {
      final resp = await http.post(
        Uri.parse('$backendUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final access = data['access_token'] as String?;
      final refresh = data['refresh_token'] as String?;
      final expiresIn = data['expires_in_seconds'] as int? ?? 3600;
      await _storeTokens(
        accessToken: access,
        refreshToken: refresh,
        expiry: DateTime.now().add(Duration(seconds: expiresIn)),
        tier: 'access',
      );
      return access != null;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> requestVerificationCode({
    required String email,
    required String password,
    required String shopName,
    required String ownerName,
  }) async {
    final resp = await http.post(
      Uri.parse('$backendUrl/auth/link'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password, 'shopName': shopName, 'ownerName': ownerName}),
    );
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> confirmVerificationCode({
    required String email,
    required String password,
    required String code,
    String? shopName,
    String? ownerName,
  }) async {
    final resp = await http.post(
      Uri.parse('$backendUrl/auth/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password, 'code': code, 'shopName': shopName, 'ownerName': ownerName}),
    );
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) {
      final access = data['access_token'] as String?;
      final refresh = data['refresh_token'] as String?;
      final expiresIn = data['expires_in_seconds'] as int? ?? (12 * 3600);
      await _storeTokens(
        accessToken: access,
        refreshToken: refresh,
        expiry: DateTime.now().add(Duration(seconds: expiresIn)),
        tier: 'device',
      );
    }
    return data;
  }

  static Future<bool> changePassword(String currentPassword, String newPassword) async {
    try {
      final token = await accessToken;
      final resp = await http.post(
        Uri.parse('$backendUrl/auth/change-password'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'currentPassword': currentPassword, 'newPassword': newPassword}),
      );
      if (resp.statusCode == 200) {
        // clear refresh tokens locally
        await _storage.delete(key: _refreshTokenKey);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> forgotPassword(String email) async {
    await http.post(
      Uri.parse('$backendUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
  }

  static Future<bool> resetPassword(String email, String code, String newPassword) async {
    try {
      final resp = await http.post(
        Uri.parse('$backendUrl/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code, 'newPassword': newPassword}),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<void> logout({bool all = false}) async {
    try {
      final token = await _storage.read(key: _accessTokenKey);
      final refresh = await _storage.read(key: _refreshTokenKey);
      await http.post(
        Uri.parse('$backendUrl/auth/logout'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'refreshToken': refresh, 'all': all}),
      );
    } catch (_) {}
    await _clearStoredTokens();
  }

  static Future<Map<String, dynamic>?> me() async {
    try {
      final token = await accessToken;
      final resp = await http.get(
        Uri.parse('$backendUrl/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<SessionRenewal> renew() async {
    return _refreshing ??= _renew().whenComplete(() => _refreshing = null);
  }

  static Future<SessionRenewal> _renew() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) return const SessionAbsent();
    if (!await isOnline()) return const SessionUnreachable();
    try {
      final resp = await http.post(
        Uri.parse('$backendUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final access = data['access_token'] as String?;
        final refresh = data['refresh_token'] as String? ?? refreshToken;
        final expiresIn = data['expires_in_seconds'] as int? ?? 3600;
        final tier = await tokenTier ?? 'access';
        await _storeTokens(
          accessToken: access,
          refreshToken: refresh,
          expiry: DateTime.now().add(Duration(seconds: expiresIn)),
          tier: tier,
        );
        return const SessionRenewed();
      }
      if (resp.statusCode == 401) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>?;
        final code = body?['code'] as String?;
        if (code == 'REFRESH_REUSE_DETECTED' || code == 'INVALID_REFRESH_TOKEN' || code == 'SESSION_EXPIRED') {
          await _clearStoredTokens();
          return const SessionRejected();
        }
      }
      return const SessionUnreachable();
    } catch (_) {
      return const SessionUnreachable();
    }
  }

  static Future<void> clearLocalSession() async {
    await _clearStoredTokens();
  }

  // Compatibility aliases for OidcService callers.
  static Future<void> clearAccessToken() async {
    await _storage.delete(key: _accessTokenKey);
  }

  static int browserSessionsEnded = 0;
}
