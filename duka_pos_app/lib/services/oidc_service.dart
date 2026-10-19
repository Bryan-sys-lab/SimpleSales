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

  /// The session the backend mints after the emailed code is presented.
  ///
  /// Stored beside the OIDC tokens rather than through them: this one is
  /// signed by our own server, so it is refreshed by `/auth/refresh` and not
  /// by the browser flow. Keeping the keys separate means a browser sign-in
  /// and a device-linked session can never be mistaken for one another,
  /// and clearing one never silently clears the other.
  static const _appSessionAccessKey = 'app_session_access_token';
  static const _appSessionRefreshKey = 'app_session_refresh_token';
  static const _appSessionExpiryKey = 'app_session_expiry';

  static const _appAuth = FlutterAppAuth();

  /// Single-flight guard: only one refresh can be in flight at a time, so
  /// concurrent callers do not each rotate the token and the second does not
  /// get `invalid_grant` and wipe the session.
  static Future<String?>? _refreshing;

  static bool get isConfigured =>
      !_issuer.contains('example.com') && _clientId.isNotEmpty;

  /// Fails loudly in release when the issuer is still the placeholder: a build
  /// without `--dart-define=OIDC_ISSUER_URL=...` can never verify, and silent
  /// failure means a shop that thinks it is online but is not.
  static void assertConfigured() {
    assert(() {
      if (!_issuer.contains('example.com') && _clientId.isNotEmpty) return true;
      throw AssertionError(
          'OIDC is not configured: set OIDC_ISSUER_URL and OIDC_CLIENT_ID');
    }());
  }

  static Future<bool> get isAuthenticated async =>
      (await accessToken) != null || (await appSessionAccessToken) != null;

  /// Saves the session returned by `/auth/verify` or `/auth/refresh`.
  static Future<void> storeAppSession({
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
  }) async {
    await _storage.write(key: _appSessionAccessKey, value: accessToken);
    await _storage.write(key: _appSessionRefreshKey, value: refreshToken);
    await _storage.write(
        key: _appSessionExpiryKey, value: expiresAt.toIso8601String());
  }

  /// The device session while it is still valid, or null.
  ///
  /// Not refreshed here: expiring it is the point of a twelve-hour lifetime,
  /// and the refresh that replaces it is an authenticated call with its own
  /// failure mode, which [`BackendService`] owns.
  static Future<String?> get appSessionAccessToken async {
    final token = await _storage.read(key: _appSessionAccessKey);
    if (token == null) return null;
    final rawExpiry = await _storage.read(key: _appSessionExpiryKey);
    final expiry = rawExpiry == null ? null : DateTime.tryParse(rawExpiry);
    if (expiry == null || !expiry.isAfter(DateTime.now())) return null;
    return token;
  }

  static Future<String?> get appSessionRefreshToken async =>
      _storage.read(key: _appSessionRefreshKey);

  static Future<void> clearAppSession() async {
    await _storage.delete(key: _appSessionAccessKey);
    await _storage.delete(key: _appSessionRefreshKey);
    await _storage.delete(key: _appSessionExpiryKey);
  }

  /// True once the till has a session, valid or not — the caller is asking
  /// whether it is worth attempting a refresh, not whether it is still live.
  static Future<bool> get hasAppSession async =>
      (await _storage.read(key: _appSessionRefreshKey)) != null;

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

    // Single-flight: only one refresh at a time. Concurrent callers wait on
    // the same future instead of each rotating the token — the second caller
    // would otherwise get `invalid_grant` from a already-used refresh token
    // and wipe the session.
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  static Future<String?> _refresh() async {
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
    } on FlutterAppAuthPlatformException catch (e) {
      // Only a real rejection (`invalid_grant`) means the refresh token is
      // dead and the session must be cleared. A network drop, a 5xx, or a
      // timeout means the tokens are still valid — keep them and let the
      // caller retry later.
      final d = '${e.platformErrorDetails} ${e.message}'.toLowerCase();
      if (d.contains('invalid_grant')) {
        await _clearStoredTokens();
      }
      return null;
    } catch (_) {
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
    await clearAppSession();
  }
}
