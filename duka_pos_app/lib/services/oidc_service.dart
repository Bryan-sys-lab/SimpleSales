import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/session_renewal.dart';

/// Self-hosted OIDC authentication for optional backend features.
///
/// The till does not depend on this service for local PIN login, inventory,
/// cash sales, reports, or backups. It is only needed when the owner connects
/// the shop to the online backend. Authorization Code + PKCE keeps the mobile
/// app a public client with no embedded client secret.
class OidcService {
  static const _issuer = String.fromEnvironment(
    'OIDC_ISSUER_URL',
    defaultValue: 'https://simplesales-keycloak.brianbmk332.workers.dev/realms/master',
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

  // There is ONE credential: the Keycloak access token below.
  //
  // It used to be two. The till also held a session minted by our own
  // server after an emailed code was presented, signed with a secret that
  // lived in the server process. That is gone: two credentials means two
  // things to revoke, two expiry clocks, and a class of token the identity
  // server has never heard of. The verify flow still proves the address and
  // still creates the account; the credential afterwards is Keycloak's, and
  // Keycloak refreshes it.

  static const _appAuth = FlutterAppAuth();

  /// Single-flight guard: only one refresh can be in flight at a time, so
  /// concurrent callers do not each rotate the token and the second does not
  /// get `invalid_grant` and wipe the session.
  static Future<SessionRenewal>? _refreshing;

  static bool get isConfigured =>
      !_issuer.contains('example.com') && _clientId.isNotEmpty;

  /// The issuer this build was compiled with.
  ///
  /// Exposed so the release-configuration check can be asked as a question
  /// about the build, rather than only as a side effect inside the service.
  static String get issuerForChecks => _issuer;

  /// The client id this build was compiled with.
  static String get clientIdForChecks => _clientId;

  /// Why this build may not be able to sign anyone in, or null when it may.
  ///
  /// Pure, and separate from the rest of the service, because the constants
  /// are fixed at compile time: a test cannot change them, so the RULE has to
  /// be testable on its own.
  static String? releaseConfigurationProblem({
    required String issuer,
    required String clientId,
    required bool isRelease,
  }) {
    // Sign-in is optional for a local-only build; backend features report
    // "under maintenance" at the point of use.
    return null;
  }

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
    final cached = await _cachedAccessToken();
    if (cached != null) return cached;
    final outcome = await renewBrowserSession();
    return outcome is SessionRenewed ? await _cachedAccessToken() : null;
  }

  /// The stored access token, when it is still fresh.
  ///
  /// Sixty seconds of margin, so a token cannot expire between the check and
  /// the request that uses it.
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

  /// Renews the browser session and says what happened.
  ///
  /// [accessToken] answers "give me a token or nothing", which cannot tell a
  /// dead session from a dead network. This one can, and the difference
  /// decides whether the till signs its cashier out or simply fails the
  /// request and keeps trading.
  ///
  /// Single-flight: only one refresh at a time. Concurrent callers wait on the
  /// same future instead of each rotating the token — the second caller would
  /// otherwise get `invalid_grant` from an already-used refresh token and
  /// wipe the session.
  static Future<SessionRenewal> renewBrowserSession() async {
    return _refreshing ??= _renew().whenComplete(() => _refreshing = null);
  }

  static Future<SessionRenewal> _renew() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) return const SessionAbsent();
    if (!isConfigured) return const SessionUnreachable();
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
      return const SessionRenewed();
    } on FlutterAppAuthPlatformException catch (e) {
      // Only a real rejection (`invalid_grant`) means the refresh token is
      // dead and the session must be cleared. A network drop, a 5xx, or a
      // timeout means the tokens are still valid — keep them and let the
      // caller retry later.
      final d = '${e.platformErrorDetails} ${e.message}'.toLowerCase();
      if (d.contains('invalid_grant')) {
        await _clearStoredTokens();
        return const SessionRejected();
      }
      return const SessionUnreachable();
    } catch (_) {
      return const SessionUnreachable();
    }
  }

  static Future<void> logout() async {
    // Counted, so a test can prove that a flow which must not open a browser
    // did not open one. Ending the provider's session launches the system
    // browser, and on a Keycloak deployment that lands the owner on a LOGIN
    // page — with a "Register" option beside it.
    browserSessionsEnded++;
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

  /// How many times a provider session has been ended in a browser.
  ///
  /// For tests only: the count is how a test proves that the ACCOUNT ERASURE
  /// did not open the provider's logout page, which is the one way that flow
  /// could show the owner a sign-up form in the middle of deleting their
  /// account.
  @visibleForTesting
  static int browserSessionsEnded = 0;

  /// Ends the session LOCALLY, without opening the provider's logout page.
  ///
  /// ## WHY THIS EXISTS
  ///
  /// [logout] asks the identity provider to end the session, which means
  /// opening the SYSTEM BROWSER at the provider's end-session endpoint with a
  /// redirect back into this app. On a Keycloak deployment that lands the
  /// owner on a LOGIN page — with a "Register" option beside it — in the
  /// middle of deleting their account. An app that is wiping itself must not
  /// answer that with a sign-up form.
  ///
  /// ## WHY IT IS SAFE
  ///
  /// The provider session outlives the account only until the account is
  /// deleted, which is what the caller is doing. The tokens on THIS device are
  /// the part that matters, and they are gone either way.
  static Future<void> clearLocalSession() async {
    await _clearStoredTokens();
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
