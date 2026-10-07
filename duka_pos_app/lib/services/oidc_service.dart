import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Self-hosted OIDC authentication for optional backend features.
///
/// The till does not depend on this service for local PIN login, inventory,
/// cash sales, reports, or backups. It is only needed when the owner connects
/// the shop to the online backend. Authorization Code + PKCE keeps the mobile
/// app a public client with no embedded client secret.
class OidcService {
  static const _issuer = String.fromEnvironment(
    'OIDC_ISSUER_URL',
    defaultValue: 'https://id.example.com/realms/duka',
  );
  static const _clientId = String.fromEnvironment(
    'OIDC_CLIENT_ID',
    defaultValue: 'duka-pos-mobile',
  );
  static const _redirectUrl = String.fromEnvironment(
    'OIDC_REDIRECT_URL',
    defaultValue: 'dukapos://callback',
  );
  static const _apiScope =
      String.fromEnvironment('OIDC_API_SCOPE', defaultValue: 'duka-api');
  static List<String> get _scope =>
      ['openid', 'profile', 'email', 'offline_access', _apiScope];

  static const _storage = FlutterSecureStorage();
  static const _accessTokenKey = 'oidc_access_token';
  static const _refreshTokenKey = 'oidc_refresh_token';
  static const _expiryKey = 'oidc_token_expiry';
  static const _idTokenKey = 'oidc_id_token';
  static const _appAuth = FlutterAppAuth();

  static bool get isConfigured =>
      !_issuer.contains('example.com') && _clientId.isNotEmpty;

  static Future<bool> get isAuthenticated async => (await accessToken) != null;

  /// Opens the system browser and completes OIDC Authorization Code + PKCE.
  static Future<bool> login() async {
    if (!isConfigured) return false;
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _clientId,
          _redirectUrl,
          issuer: _issuer,
          scopes: _scope,
        ),
      );
      await _storeTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        idToken: result.idToken,
        expiry: result.accessTokenExpirationDateTime,
      );
      return result.accessToken != null;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> get accessToken async {
    final token = await _storage.read(key: _accessTokenKey);
    final rawExpiry = await _storage.read(key: _expiryKey);
    final expiry = rawExpiry == null ? null : DateTime.tryParse(rawExpiry);
    if (token != null &&
        expiry != null &&
        expiry.isAfter(DateTime.now().add(const Duration(seconds: 60)))) {
      return token;
    }

    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null || !isConfigured) return null;
    try {
      final result = await _appAuth.token(TokenRequest(
        _clientId,
        _redirectUrl,
        issuer: _issuer,
        refreshToken: refreshToken,
        scopes: _scope,
      ));
      await _storeTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken ?? refreshToken,
        idToken: result.idToken,
        expiry: result.accessTokenExpirationDateTime,
      );
      return result.accessToken;
    } catch (_) {
      await _clearStoredTokens();
      return null;
    }
  }

  static Future<void> logout() async {
    final idToken = await _storage.read(key: _idTokenKey);
    try {
      if (idToken != null && isConfigured) {
        await _appAuth.endSession(EndSessionRequest(
          idTokenHint: idToken,
          postLogoutRedirectUrl: _redirectUrl,
          issuer: _issuer,
        ));
      }
    } catch (_) {
      // Local credential clearing must still happen if the provider is down.
    } finally {
      await _clearStoredTokens();
    }
  }

  static Future<void> clearAccessToken() async {
    await _storage.delete(key: _accessTokenKey);
  }

  static Future<void> _storeTokens({
    required String? accessToken,
    required String? refreshToken,
    required String? idToken,
    required DateTime? expiry,
  }) async {
    if (accessToken != null) {
      await _storage.write(key: _accessTokenKey, value: accessToken);
    }
    if (refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
    if (idToken != null) await _storage.write(key: _idTokenKey, value: idToken);
    if (expiry != null) {
      await _storage.write(key: _expiryKey, value: expiry.toIso8601String());
    }
  }

  static Future<void> _clearStoredTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _expiryKey);
    await _storage.delete(key: _idTokenKey);
  }
}
