import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import '../models/session_renewal.dart';
import 'etims/etims_service.dart';
import 'oidc_service.dart';
import 'row_scope.dart';
import 'workspace_service.dart';
import 'portfolio_kpis.dart';

/// Why a verification step failed.
///
/// One enum rather than strings in the exceptions, because the message a shop
/// sees is a translation decision and the cause is a fact: "the code is wrong,
/// three attempts left" and "the code expired, ask for a new one" are different
/// situations with different next steps, and translating at the throw site
/// would put the locale in the wrong layer.
enum VerificationFailure {
  /// The backend has no realm credentials or no EmailJS keys.
  notConfigured,

  /// The identity server could not be reached.
  identityUnavailable,

  /// The code was created but the email never went out.
  emailUnavailable,

  /// The code ran out of time.
  expired,

  /// The code, or the PIN, was wrong.
  invalidCode,

  /// Five wrong attempts burnt the code.
  tooManyAttempts,

  /// Three codes in fifteen minutes; the mailbox is being protected.
  tooManyCodes,

  /// The account has no shop and none was supplied to create one.
  shopSetupRequired,

  /// No signal, DNS failure, or the server is down.
  network,

  /// Anything else. Rendered as the generic link failure.
  unknown,
}

/// A failed verification step, carrying the cause and the state the UI needs
/// to say something useful.
class VerificationException implements Exception {
  const VerificationException(this.failure, {this.attemptsRemaining});

  final VerificationFailure failure;
  final int? attemptsRemaining;

  @override
  String toString() => 'VerificationException($failure)';
}

/// Why a Forgot-PIN step could not complete.
enum PinResetFailure {
  /// No network: the reset cannot be attempted offline, by design.
  offline,

  /// The server did not answer in time.
  timeout,

  /// Too many attempts: the rate limit is running.
  tooManyAttempts,

  /// The code was wrong or has expired.
  codeRejected,

  /// The email is not on any account on this backend.
  emailUnknown,

  /// The request step did not return a challenge to confirm against.
  challengeMissing,

  /// Anything else the server said.
  server,
}

/// Thrown by the Forgot-PIN steps so the dialog can name the cause.
class PinResetException implements Exception {
  const PinResetException(this.failure);

  final PinResetFailure failure;

  @override
  String toString() => 'PinResetException($failure)';
}

/// Where the code was sent, and for how long it is still good.
class VerificationChallenge {
  const VerificationChallenge({
    required this.challengeId,
    required this.maskedEmail,
    required this.expiresInSeconds,
  });

  factory VerificationChallenge.fromJson(Map<String, dynamic> json) =>
      VerificationChallenge(
        challengeId: json['challenge_id'] as String? ?? '',
        maskedEmail: json['email'] as String? ?? '',
        expiresInSeconds: (json['expires_in_seconds'] as num?)?.toInt() ?? 0,
      );

  final String challengeId;
  final String maskedEmail;
  final int expiresInSeconds;
}

/// What a verified identity means to the till: which shop, and the session to
/// call the backend with.
class VerifiedIdentity {
  const VerifiedIdentity({
    required this.tenantId,
    required this.shopName,
  });

  factory VerifiedIdentity.fromJson(Map<String, dynamic> json) =>
      VerifiedIdentity(
        tenantId: json['tenant_id'] as String? ?? '',
        shopName: json['shop_name'] as String? ?? '',
      );

  /// The shop the account runs.
  final String tenantId;

  /// What the shop is called.
  final String shopName;
}

/// Backend API service using self-hosted OIDC tokens instead of Supabase.
/// Keeps the same interface as the old backend_service.dart so the
/// rest of the app doesn't need changes.
class BackendService {
  static bool _initialized = false;
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  ));

  static SharedPreferences? _prefs;

  /// Marks a request that has already had one chance to renew its session.
  static const String _authRetriedKey = 'auth_retried';

  /// The URL a build falls back to when `--dart-define=BACKEND_URL=...` is
  /// missing.
  ///
  /// Named so a test can recognise it: a RELEASE build that still carries
  /// this URL points every shop's till at a server on the phone's own
  /// machine — no KRA receipt for the money taken, no M-Pesa, no sync, and no
  /// error message to explain any of it.
  static const String defaultBackendUrl = 'https://localhost:3000/api';

  static const backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: defaultBackendUrl,
  );

  /// Why this build may not reach a server, or null when it may.
  ///
  /// Pure, and separate from the rest of the service, because the constant
  /// [backendUrl] is fixed at compile time: a test cannot change it, so the
  /// RULE has to be testable on its own.
  ///
  /// A debug build is never a problem — localhost is exactly where the
  /// development server lives. A release build with no address is: it is the
  /// build that reaches a shop, and a shop whose till cannot reach the backend
  /// cannot issue a tax receipt for the money it has taken.
  ///
  /// It is a NOTICE, not a gate. The build still starts and the till still
  /// sells; see [BuildConfiguration] for where the answer is shown.
  static String? releaseConfigurationProblem({
    required String url,
    required bool isRelease,
  }) {
    if (!isRelease) return null;
    if (url.trim().isEmpty) {
      return 'BACKEND_URL is empty. Rebuild with '
          '--dart-define=BACKEND_URL=https://your-backend/api';
    }
    if (url == defaultBackendUrl) {
      return 'BACKEND_URL was never set, so this build points at '
          '$defaultBackendUrl. Rebuild with '
          '--dart-define=BACKEND_URL=https://your-backend/api';
    }
    if (url.startsWith('http://')) {
      return 'BACKEND_URL ($url) is plaintext. Staff PINs, usernames and OIDC '
          'tokens would cross the network in the clear. Use https://';
    }
    return null;
  }

  static Future<SharedPreferences> get _prefsInstance async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Future<void> ensureInitialized() async {
    if (_initialized) return;

    // Refuse plaintext transport: the backend carries staff PINs, OIDC bearer
    // tokens, and KRA tax-compliance data. A non-HTTPS URL would send all of
    // that in cleartext.
    if (backendUrl.startsWith('http://')) {
      if (kReleaseMode) {
        throw StateError(
            'Insecure BACKEND_URL ($backendUrl): use https:// to protect '
            'staff credentials and OIDC tokens in transit.');
      }
      debugPrint('WARNING: BACKEND_URL is http:// — staff PINs, usernames, '
          'and OIDC tokens will transit in plaintext. Set BACKEND_URL to '
          'https:// for any non-local deployment.');
    }

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // The ONE credential: the Keycloak access token.
        //
        // It used to be two — the browser session first, and the server's own
        // device session second. A shop that signed in through Keycloak kept
        // using that token; a shop that tapped Verify and typed a mailed code
        // used the session the backend minted for it. There is one now, and
        // the server accepts nothing else.
        final token = await OidcService.accessToken;
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        // The tenant this shop on this device maps to, NOT a global preference.
        //
        // A device can hold several shops, and each has its own tenant: reading
        // the active tenant from the registry means the second shop's requests
        // are sent under the second shop's tenant instead of whichever shop
        // verified most recently. An unlinked shop sends no tenant header at all
        // rather than borrowing a neighbour's.
        final selectedTenant = await WorkspaceService.activeTenantId();
        if (selectedTenant != null) {
          options.headers['x-tenant-id'] = selectedTenant;
        }
        options.headers['Content-Type'] = 'application/json';
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 &&
            error.requestOptions.extra[_authRetriedKey] != true) {
          final requestOptions = error.requestOptions;
          // Marked BEFORE the retry, because the retry goes back through this
          // same interceptor: without the flag, a request that is refused
          // twice would renew, retry, be refused, renew again — a loop that
          // ends only when the phone runs out of battery.
          requestOptions.extra[_authRetriedKey] = true;

          // The Keycloak session, if there is one.
          final SessionRenewal browser =
              await OidcService.renewBrowserSession();
          if (browser is SessionRenewed) {
            final renewed = await OidcService.accessToken;
            if (renewed != null) {
              requestOptions.headers['Authorization'] = 'Bearer $renewed';
              try {
                return handler.resolve(await _dio.fetch(requestOptions));
              } on DioException catch (_) {
                return handler.next(error);
              }
            }
          }
          if (browser is SessionRejected) {
            // The provider refused the refresh token. The session is over.
            await OidcService.logout();
            return handler.next(error);
          }
          // Unreachable or absent: nothing is known to be wrong with the
          // session, so nothing is cleared. The request fails; the till keeps
          // selling and the next request tries again.
        }
        return handler.next(error);
      },
    ));

    _initialized = true;
  }

  /// Points the till at the shop the verify flow just linked.
  ///
  /// ## WHY NO TOKEN IS STORED HERE
  ///
  /// The backend used to mint a session of its own here and hand it back.
  /// It does not any more: the credential is Keycloak's, and Keycloak is the
  /// only thing that issues one. The verify flow's job now ends at "the
  /// account exists, the address is proven, and here is the shop" — and the
  /// till signs in to Keycloak for the token, which is the authority that
  /// matters.
  ///
  /// So there is nothing to store but the SHOP: which workspace it is, which
  /// tenant it maps to, and what it is called. The credential that opens it
  /// comes from the identity server, and it is refreshed there.
  static Future<void> _adoptVerifiedIdentity(VerifiedIdentity identity) async {
    if (identity.tenantId.isNotEmpty) {
      // Recorded against the ACTIVE workspace, and read back from there — see
      // [WorkspaceService.activeTenantId] for why a global key is wrong here.
      await (await _prefsInstance).remove(_legacyTenantKey);
      await WorkspaceService.register(
          workspaceKey: await WorkspaceService.activeWorkspaceKey(),
          tenantId: identity.tenantId,
          shopName: (await WorkspaceService.activeShopName()) ?? 'Shop');
    }
  }

  // ---------------------------------------------------------------- verification

  /// Step one of Verify: create the online account for this shop and post a
  /// 6-digit code to its email address.
  ///
  /// The [pin] is the shop's own 6-digit admin PIN, and it is verified against
  /// the local hash on the device before this method is ever reached — the
  /// caller refuses a wrong one rather than sending it over the wire. The
  /// backend cannot verify it (the hash lives in this phone's database), so the
  /// server treats it as an opaque value bound into the challenge, which is
  /// what ties the two halves of the flow to the same person.
  ///
  /// The PIN is still a password for the owner session, so transmitting it
  /// puts it somewhere this phone does not control. That is the server contract
  /// as it stands; the form that does not is a server-issued nonce the till
  /// signs with a key derived from the PIN. Until the backend accepts that, the
  /// mitigations live on this side: local verification with a till-wide
  /// lockout before the PIN is sent, and a value that is only ever sent to the
  /// one endpoint that needs it.
  static Future<VerificationChallenge> requestVerificationCode({
    required String email,
    required String pin,
    required String shopName,
    required String ownerName,
  }) async {
    await ensureInitialized();
    try {
      final response = await _dio.post('$backendUrl/auth/link', data: {
        'email': email,
        'pin': pin,
        'shopName': shopName,
        'ownerName': ownerName,
      });
      return VerificationChallenge.fromJson(
          response.data as Map<String, dynamic>? ?? const {});
    } on DioException catch (error) {
      throw verificationFailure(error);
    }
  }

  /// Step two of Verify: hand back the code from the email.
  ///
  /// On success this points the till at the shop the account runs, and then
  /// SIGNS IN TO KEYCLOAK for the credential.
  ///
  /// ## WHY THE SIGN-IN IS HERE AND NOT IN THE SERVER
  ///
  /// The server used to mint a session of its own and hand it back. It does
  /// not any more: there is one credential in the whole system, a Keycloak
  /// access token, and only the identity server may issue one. So the account
  /// is created and activated by the server, and the token is collected by the
  /// till — which is the party that will present it on every request.
  ///
  /// The shop is recorded first, so that a sign-in which is interrupted still
  /// leaves the till pointing at the right shop.
  static Future<VerifiedIdentity> confirmVerificationCode({
    required String email,
    required String pin,
    required String code,
  }) async {
    await ensureInitialized();
    try {
      final response = await _dio.post('$backendUrl/auth/verify', data: {
        'email': email,
        'pin': pin,
        'code': code,
      });
      final identity = VerifiedIdentity.fromJson(
          response.data as Map<String, dynamic>? ?? const {});
      await _adoptVerifiedIdentity(identity);
      // The credential, from the authority that issues them.
      if (!await OidcService.login()) {
        throw StateError('Could not sign in to the identity server');
      }
      if (identity.shopName.isNotEmpty) {
        await WorkspaceService.register(
          workspaceKey: await WorkspaceService.activeWorkspaceKey(),
          tenantId: identity.tenantId,
          shopName: identity.shopName,
        );
      }
      return identity;
    } on DioException catch (error) {
      throw verificationFailure(error);
    }
  }

  /// Maps a backend answer onto the one enum the UI translates from.
  ///
  /// Public because the taxonomy is the contract between the service and the
  /// screen: a new failure the backend can report is a new case here, and a
  /// test that walks the whole list is the only thing that keeps the two in
  /// step.
  ///
  /// The specific codes are matched BEFORE the status codes, because two
  /// failures share a status: a burnt code and a shouted-down mailbox both come
  /// back 429, and an unreachable identity server and an email that never left
  /// both come back 502. Matching the status first would collapse "ask for a
  /// new code" into "we could not reach the server", which is a sentence that
  /// sends the owner off to fix the wrong thing.
  static VerificationException verificationFailure(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final String? code = data is Map ? data['code'] as String? : null;
    switch (code) {
      case 'TOO_MANY_CODES':
        return const VerificationException(VerificationFailure.tooManyCodes);
      case 'TOO_MANY_ATTEMPTS':
        return const VerificationException(VerificationFailure.tooManyAttempts);
      case 'VERIFICATION_EXPIRED':
        return const VerificationException(VerificationFailure.expired);
      case 'VERIFICATION_INVALID':
        final remaining =
            data is Map ? data['attempts_remaining'] as num? : null;
        return VerificationException(VerificationFailure.invalidCode,
            attemptsRemaining: remaining?.toInt());
      case 'SHOP_SETUP_REQUIRED':
        return const VerificationException(
            VerificationFailure.shopSetupRequired);
      case 'VERIFICATION_NOT_CONFIGURED':
        return const VerificationException(VerificationFailure.notConfigured);
      case 'IDENTITY_UNAVAILABLE':
        return const VerificationException(
            VerificationFailure.identityUnavailable);
      case 'EMAIL_UNAVAILABLE':
        return const VerificationException(
            VerificationFailure.emailUnavailable);
    }
    if (status == 429) {
      return const VerificationException(VerificationFailure.tooManyCodes);
    }
    if (status == 503) {
      return const VerificationException(VerificationFailure.notConfigured);
    }
    if (status == 502) {
      return const VerificationException(
          VerificationFailure.identityUnavailable);
    }
    if (status == null) {
      return const VerificationException(VerificationFailure.network);
    }
    return const VerificationException(VerificationFailure.unknown);
  }

  static Future<String?> get tenantId async =>
      WorkspaceService.activeTenantId();

  /// The single global key the active tenant used to live under.
  ///
  /// Kept only so an older install's value can be cleared, never read: a global
  /// `tenant_id` was the cross-shop leak described on
  /// [WorkspaceService.activeTenantId].
  static const _legacyTenantKey = 'tenant_id';

  /// Binds a tenant to the shop that is active right now.
  static Future<void> _setTenant(String tenantId) async {
    if (tenantId.trim().isEmpty) return;
    await (await _prefsInstance).remove(_legacyTenantKey);
    await WorkspaceService.register(
      workspaceKey: await WorkspaceService.activeWorkspaceKey(),
      tenantId: tenantId,
      shopName: (await WorkspaceService.activeShopName()) ?? 'Shop',
    );
  }

  /// A `DELETE` that returns true for any 2xx.
  ///
  /// Dio has no `delete` that both sends a body and swallows a 404 the way the
  /// callers here want, so the shape is stated once. A 404 is `true`: the
  /// account the caller is deleting is already gone, which for a deletion is
  /// success, and re-reporting it would have the owner delete twice.
  ///
  /// Takes the PATH ONLY and builds the absolute URL itself. A caller that
  /// could pass its own path slipped through with a relative one —
  /// `'auth/account'` — which Dio resolved against an empty `baseUrl`, so the
  /// request never left the device while the UI reported "the server could not
  /// be reached". The client's `_dio` has no `baseUrl` on purpose (every other
  /// call site is absolute), so a relative path is a silent no-op rather than a
  /// compile error: that is why the URL is built HERE and nowhere else.
  static Future<bool> deleteRequest(
      String path, Map<String, dynamic> data) async {
    await ensureInitialized();
    final String url = path.startsWith('http') ? path : '$backendUrl/$path';
    try {
      final response = await _dio.delete(url, data: data);
      return response.statusCode == null ||
          (response.statusCode! >= 200 && response.statusCode! < 300);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return true;
      rethrow;
    }
  }

  // ---------------------------------------------------------------- PIN reset

  /// Step one of Forgot PIN: ask for a code at the email on the account.
  ///
  /// The email is the only thing the backend will accept, and the code comes
  /// back the same way a Verify code does. There is deliberately NO local-only
  /// path: a reset that worked offline would let anyone holding an unlocked
  /// phone change the owner PIN and walk into the owner session, which is the
  /// entire reason the PIN exists.
  ///
  /// Returns the challenge id, which the confirm step needs.
  static Future<String> requestPinReset({required String email}) async {
    await ensureInitialized();
    try {
      final response = await _dio.post('$backendUrl/auth/pin-reset/request',
          data: {'email': email.trim()});
      final challenge =
          response.data is Map ? response.data['challengeId'] as String? : null;
      if (challenge == null || challenge.isEmpty) {
        throw const PinResetException(PinResetFailure.challengeMissing);
      }
      return challenge;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw const PinResetException(PinResetFailure.timeout);
      }
      if (e.type == DioExceptionType.connectionError) {
        throw const PinResetException(PinResetFailure.offline);
      }
      final status = e.response?.statusCode;
      if (status == 429) {
        throw const PinResetException(PinResetFailure.tooManyAttempts);
      }
      if (status == 404) {
        // The email is not on any account here.
        throw const PinResetException(PinResetFailure.emailUnknown);
      }
      throw const PinResetException(PinResetFailure.server);
    }
  }

  /// Step two of Forgot PIN: exchange a mailed code for a new owner PIN.
  ///
  /// Returns true when the server accepted the code. The caller then writes the
  /// new hash locally — the backend cannot know a hash it never saw, so the new
  /// PIN's hash is created on this device and never leaves it.
  static Future<bool> confirmPinReset({
    required String email,
    required String challengeId,
    required String code,
  }) async {
    await ensureInitialized();
    try {
      final response =
          await _dio.post('$backendUrl/auth/pin-reset/confirm', data: {
        'email': email.trim(),
        'challengeId': challengeId,
        'code': code.trim(),
      });
      return response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 429) {
        throw const PinResetException(PinResetFailure.tooManyAttempts);
      }
      if (status == 400 || status == 401 || status == 403) {
        throw const PinResetException(PinResetFailure.codeRejected);
      }
      if (status == 404) {
        throw const PinResetException(PinResetFailure.emailUnknown);
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        throw const PinResetException(PinResetFailure.offline);
      }
      throw const PinResetException(PinResetFailure.server);
    }
  }

  static Future<bool> get isBackendLinked async => (await tenantId) != null;

  static Future<List<Map<String, dynamic>>> listMyShops() async {
    await ensureInitialized();
    final response = await _dio.get('$backendUrl/tenant/shops');
    return (response.data['shops'] as List? ?? const [])
        .whereType<Map>()
        .map((shop) => Map<String, dynamic>.from(shop))
        .toList();
  }

  /// The KPIs of every shop this account runs, in one body.
  ///
  /// A second shop used to mean reading the ledger twice and adding the figures
  /// on the phone — on the device and the moment the owner least has signal. The
  /// backend now aggregates across the caller's own tenants, so the portfolio
  /// view is one request.
  ///
  /// [from] and [to] bound the window, matching the per-shop reports so the two
  /// screens never disagree about "this month".
  ///
  /// Throws when the account links no shop: a caller who is a cashier in every
  /// shop gets an empty portfolio from the server rather than an error, and this
  /// surfaces it as an empty result so the screen can say so.
  static Future<PortfolioKpis> portfolioKpis({
    required DateTime from,
    required DateTime to,
  }) async {
    await ensureInitialized();
    final response = await _dio.get<Map<String, dynamic>>(
      '$backendUrl/tenant/portfolio',
      queryParameters: <String, String>{
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
      },
    );
    return PortfolioKpis.fromJson(response.data ?? const <String, dynamic>{});
  }

  static Future<void> switchShop(String selectedTenantId) async {
    if (selectedTenantId.trim().isEmpty) {
      throw ArgumentError.value(selectedTenantId, 'selectedTenantId');
    }
    final existing =
        await WorkspaceService.workspaceForTenant(selectedTenantId);
    if (existing == null) {
      throw StateError('This shop is not set up on this device yet');
    }
    // Setting the active workspace is now the whole operation: the tenant is
    // derived from it, so a stale global value can no longer outlive the shop
    // switch that made it wrong.
    await (await _prefsInstance).remove(_legacyTenantKey);
    await WorkspaceService.setActiveWorkspace(existing);
  }

  static Future<Map<String, dynamic>?> authenticateStaff({
    required String username,
    required String pin,
  }) async {
    await ensureInitialized();
    try {
      final response = await _dio.post('$backendUrl/tenant/staff/authenticate',
          data: {'username': username, 'pin': pin});
      final data = response.data as Map<String, dynamic>? ?? const {};
      return data.isNotEmpty ? data : null;
    } on DioException catch (_) {
      return null;
    }
  }

  /// Platform backend configuration is restricted to the explicit system
  /// administrator allowlist; shop admins manage only their own shop data.
  static Future<void> requireSystemAdmin() async {
    if (!await OidcService.isAuthenticated && !await OidcService.login()) {
      throw StateError('System administrator authentication required');
    }
    await ensureInitialized();
    await _dio.get('$backendUrl/system/access');
  }

  static Future<void> configureTenantAsSystemAdmin(
      {required String tenantId, required int channelId}) async {
    await requireSystemAdmin();
    await _dio.patch('$backendUrl/system/tenants/$tenantId/settings',
        data: {'mpesaEnabled': true, 'paymentChannelId': channelId});
  }

  /// One-time backend registration after the owner completes OIDC login.
  static Future<void> linkShopToBackend({
    required String shopName,
    required String ownerName,
    String email = '',
  }) async {
    if (!await OidcService.isAuthenticated && !await OidcService.login()) {
      throw StateError('Could not authenticate with backend');
    }
    await ensureInitialized();

    // Provision tenant via API
    try {
      final response = await _dio.post('$backendUrl/tenant/provision', data: {
        'shopName': shopName,
        'ownerName': ownerName,
        'email': email,
      });

      final tid = response.data['tenant_id'];
      if (tid != null) {
        await _setTenant(tid);
        await WorkspaceService.register(
            workspaceKey: await WorkspaceService.activeWorkspaceKey(),
            tenantId: tid,
            shopName: shopName);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        // The OIDC account may already be linked from an earlier attempt.
        //
        // Adopt the server's tenant ONLY if it is already bound to THIS shop's
        // workspace. A 409 means "this account already has a tenant" — it says
        // nothing about WHICH shop that tenant belongs to, and one OIDC account
        // can hold several. Adopting unconditionally bound the wrong shop's
        // tenant here, after which this shop's products, staff and sales were
        // written into the other shop's tenant: a cross-tenant write, and
        // exactly what row-level scoping exists to prevent.
        final existingTenantId =
            e.response?.data is Map ? e.response?.data['tenant_id'] : null;
        if (existingTenantId is String && existingTenantId.isNotEmpty) {
          final bound =
              await WorkspaceService.workspaceForTenant(existingTenantId);
          // Refuse only when ANOTHER shop on THIS device already holds that
          // tenant. That is the cross-shop write the guard exists to stop.
          //
          // Two cases must still be allowed, and the first version of this guard
          // broke both:
          //
          //   * `bound == null` — the tenant is on the server but not in this
          //     device's registry, which is every fresh install, reinstall and
          //     second device. Refusing there left a legitimate shop
          //     permanently unlinked while telling it "another shop on this
          //     device", which was false.
          //   * `bound == active` — a genuine retry of this shop's own link.
          //
          // `workspaceForTenant` scans the LOCAL registry only, so a tenant held
          // by a shop on another device reads as null here; adopting it is what
          // the owner chose when they signed in with that account.
          if (bound == null ||
              bound == await WorkspaceService.activeWorkspaceKey()) {
            await _setTenant(existingTenantId);
            return;
          }
        }
        // The account is linked to a DIFFERENT shop on this device (or on
        // another). Refuse rather than guess: the owner must choose which shop
        // they are linking, and a wrong guess posts this shop's ledger into
        // another shop's tenant.
        throw StateError(
          'This account is already linked to another shop on this device. '
          'Switch to that shop, or use a different account.',
        );
      }
      throw StateError('Could not register shop: ${e.message}');
    }
  }

  // ---------------- Row-level scope ----------------

  /// Where this shop recorded the tenant its `remote_id`s were minted under.
  ///
  /// Lives in the shop's OWN database, so it is per-workspace by construction —
  /// the same property that makes each shop's file its own isolation. A global
  /// preference would let shop B inherit shop A's provenance and pass a check it
  /// should fail.
  static const _remoteScopeKey = 'remote_id_scope_tenant';

  /// Enforces the row-level scope rule for this shop, and drops the rows that
  /// no longer satisfy it.
  ///
  /// Called before any payload that carries a cached `remote_id`. When the
  /// active tenant differs from the one recorded when those ids were minted,
  /// the ids are cleared rather than sent:
  ///
  ///   * a relink under a new tenant starts clean, and the server mints fresh
  ///     ids inside the namespace the shop is actually bound to;
  ///   * a stale id can never be resolved against a foreign row, so there is no
  ///     cross-tenant write and no overwrite of another shop's data.
  ///
  /// Nothing is thrown on a mismatch: the whole point is that this is a normal,
  /// recoverable state a shop reaches by relinking. The exception type exists
  /// for a caller that needs to refuse rather than repair.
  static Future<RowScope> _assertRowsInScope() async {
    final scope = await RowScope.current();
    if (scope == null) {
      throw const RowScopeException(RowScopeFailure.notLinked);
    }
    final recorded = await DatabaseHelper.instance.getSetting(_remoteScopeKey);
    if (recorded == null || recorded == scope.tenantId) {
      // Either first contact or an unchanged binding. Record the scope so a
      // later change is detectable.
      if (recorded != scope.tenantId) {
        await DatabaseHelper.instance
            .setSetting(_remoteScopeKey, scope.tenantId);
      }
      return scope;
    }
    // The binding moved under rows that still carry ids from the old tenant.
    await _invalidateStaleRemoteIds();
    await DatabaseHelper.instance.setSetting(_remoteScopeKey, scope.tenantId);
    return scope;
  }

  /// Clears every cached `remote_id` so the next sync mints fresh ones.
  ///
  /// Only the CACHED ids are dropped. The rows themselves are untouched — a
  /// product the shop still sells is still its product, and the only thing that
  /// changes is which server row it maps to.
  ///
  /// The staff deletion tombstones are cleared as well, which matters more than
  /// it looks: a tombstone holds the `remote_id` of a cashier who was removed,
  /// and replaying that id against a different tenant's namespace would try to
  /// delete a row in another shop.
  static Future<void> _invalidateStaleRemoteIds() async {
    await DatabaseHelper.instance.clearAllRemoteIds();
    await DatabaseHelper.instance.clearAllDeletionTombstones();
  }

  /// The scope the shop's outbound rows are written under.
  ///
  /// Throws [RowScopeException] when the shop is not linked, which a caller
  /// wanting a hard refusal can catch.
  static Future<RowScope> requireRowScope() async {
    final scope = await RowScope.current();
    if (scope == null) {
      throw const RowScopeException(RowScopeFailure.notLinked);
    }
    return scope;
  }

  /// Enable/disable M-Pesa payments
  static Future<void> setMpesaEnabled(bool enabled, {int? channelId}) async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) throw StateError('Shop is not linked to backend');

    await _dio.patch('$backendUrl/tenant/settings', data: {
      'mpesaEnabled': enabled,
      if (channelId != null) 'paymentChannelId': channelId,
    });
  }

  /// Enable/disable eTIMS flag
  static Future<void> setEtimsEnabled(bool enabled) async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) throw StateError('Shop is not linked to backend');

    await _dio.patch('$backendUrl/tenant/settings', data: {
      'etimsEnabled': enabled,
    });
  }

  // ---------------- eTIMS ----------------

  /// Asks the backend to issue a KRA receipt for one sale.
  ///
  /// Called from the pending queue rather than from the checkout path, and that
  /// placement is the whole design: the customer has already paid and the sale
  /// is already committed, so a KRA outage here delays an invoice and nothing
  /// else. Issuing inline would mean an unreachable tax authority can stop a
  /// shop taking money.
  ///
  /// Amounts go over the wire as integer minor units, matching how they are
  /// stored. The backend contract predates the move to minor units and speaks
  /// major units for catalogue prices, so every figure here is converted
  /// explicitly rather than relying on the wire shape — sending a `Money`
  /// object would serialise as the text "Money(4050 minor units)".
  static Future<EtimsIssueResult> issueEtimsReceipt(
    Map<String, dynamic> payload, {
    String? deviceId,
    CancelToken? cancelToken,
  }) async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) {
      // Not linked: a configuration problem, but transient — the sale stays
      // queued and retries once the shop links, instead of being rejected.
      throw const EtimsNotLinkedException(
          'This shop is not linked to the backend, so receipts cannot be issued.');
    }

    final receiptNumber = payload['receipt_number'] as String?;
    final response = await _dio.post(
      '$backendUrl/etims/receipts',
      data: {...payload, if (deviceId != null) 'device_id': deviceId},
      options: Options(headers: {
        if (receiptNumber != null && receiptNumber.trim().isNotEmpty)
          'Idempotency-Key': receiptNumber.trim(),
      }),
      cancelToken: cancelToken,
    );
    final data = response.data as Map<String, dynamic>? ?? const {};
    // Respect the backend's own status: a returned number is not enough — KRA
    // may return a number with status "pending" or "rejected", and the till
    // must not treat it as issued.
    final status = data['status'] as String?;
    if (status != null && status != 'issued' && status != 'success') {
      throw EtimsRejectedException(
          'KRA has not issued this receipt (status: $status).');
    }
    final kraReceiptNumber = data['kra_receipt_number'];
    if (kraReceiptNumber is! String || kraReceiptNumber.trim().isEmpty) {
      throw StateError('The backend returned no KRA receipt number');
    }
    return EtimsIssueResult(
      kraReceiptNumber: kraReceiptNumber.trim(),
      verificationUrl: data['verification_url'] as String?,
      qrPayload: data['qr_payload'] as String?,
    );
  }

  /// How many receipts are still waiting to be issued.
  static Future<EtimsQueueStatus> getEtimsQueueStatus() async {
    await ensureInitialized();
    final response = await _dio.get('$backendUrl/etims/status');
    final data = response.data as Map<String, dynamic>? ?? const {};
    return EtimsQueueStatus(
      configured: data['configured'] == true,
      pending: (data['pending_upload'] as num?)?.toInt() ?? 0,
      rejected: (data['rejected'] as num?)?.toInt() ?? 0,
      deviceStatus: data['device_status'] as String?,
      tin: data['tin'] as String?,
    );
  }

  /// The Z-report for a day, as KRA requires it at close of trade.
  ///
  /// Generated server-side because it has to reconcile against the receipts
  /// KRA has actually accepted, which the till cannot know.
  static Future<Map<String, dynamic>> getEtimsZReport({
    DateTime? date,
  }) async {
    await ensureInitialized();
    final response =
        await _dio.get('$backendUrl/etims/z-report', queryParameters: {
      if (date != null) 'date': _isoDate(date),
    });
    return (response.data as Map<String, dynamic>?) ?? const {};
  }

  static String _isoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// Pushes the till's TIN and device registration to the backend.
  ///
  /// The TIN is legally significant and is never accepted from a client without
  /// the backend confirming it against KRA's registration.
  static Future<void> registerEtimsDevice({
    required String tin,
    required String deviceId,
    String? deviceName,
  }) async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) {
      throw const EtimsNotLinkedException(
          'Link your shop to the backend before registering an eTIMS device.');
    }
    await _dio.post('$backendUrl/etims/device', data: {
      'tin': tin,
      'device_id': deviceId,
      if (deviceName != null && deviceName.isNotEmpty)
        'device_name': deviceName,
    });
  }

  /// Pushes a stock correction to the backend.
  ///
  /// `/products/sync` no longer carries `stockQty` for existing rows because
  /// the server is the authority there, so this is how a break, a delivery or a
  /// count reaches it. Best effort: the local ledger is already updated, and a
  /// failed push is surfaced rather than silently dropped.
  ///
  /// NEVER THROWS. The local adjustment has already been written by the time
  /// this is called, so an exception escaping here would be caught by the
  /// caller's error handler and reported as a failed adjustment — and the
  /// natural response to "the adjustment failed" is to run it again, which
  /// applies the delta twice. A push that did not happen is a "saved on this
  /// phone only" outcome, not a failure of the adjustment.
  static Future<bool> adjustStockOnBackend({
    required Product product,
    required int delta,
    String? reason,
    String? staffProfileId,
  }) async {
    try {
      await ensureInitialized();
      final tid = await tenantId;
      if (tid == null) return false;
      final remoteId = product.remoteId;
      if (remoteId == null) return false;
      // The remote id names a row in one tenant's namespace. If the shop has
      // been relinked since that id was minted, the write would land on a
      // foreign row, so the scope is checked rather than assumed.
      await _assertRowsInScope();
      await _dio.post('$backendUrl/products/stock-adjust', data: {
        'product_id': remoteId,
        'delta': delta,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (staffProfileId != null) 'staff_profile_id': staffProfileId,
      });
      return true;
    } on DioException {
      return false;
    } catch (_) {
      // A scope violation, a misconfigured backend, an unreachable tenant —
      // none of them undo the local adjustment, so none of them may be
      // reported as one.
      return false;
    }
  }

  /// Builds the single shared product payload both sync paths send to the
  /// backend. Extracted so the single-row and bulk paths can never drift apart:
  /// a field added to one is added to both.
  ///
  /// Major units on the wire: the backend contract predates the move to
  /// integer cents and is expressed in shillings. Sending a Money object
  /// here would serialise as "Money(4050 minor units)".
  static Map<String, dynamic> _productPayload(Product product) => {
        'id': product.id,
        'remoteId': product.remoteId,
        'name': product.name,
        'category': product.category,
        'costPrice': product.costPrice.asMajor,
        'sellPrice': product.sellPrice.asMajor,
        'stockQty': product.stockQty,
        'reorderLevel': product.reorderLevel,
        'bottleMl': product.bottleMl,
        'halfPrice': product.halfPrice?.asMajor,
        'quarterPrice': product.quarterPrice?.asMajor,
        'exciseStampBatch': product.exciseStampBatch,
        'active': product.active,
      };

  /// Syncs one product to the backend immediately after it is edited.
  ///
  /// The bulk path runs on the auto-sync timer, so a price or name change is
  /// invisible to the backend for up to six hours — long enough for the shop to
  /// sell at a stale price. Pushing the single edited row keeps the catalogue
  /// current without re-sending the whole inventory.
  static Future<void> syncProductToBackend(Product product) async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) return;
    if (product.id == null) return;
    // The same scope check the bulk syncs carry.
    //
    // This path is the single-row one, taken on EVERY product save
    // (`inventory_screen._pushProductInBackground`), so it was the busiest
    // unguarded write in the app: a price edited after a relink posted a
    // `remote_id` minted under the previous tenant, and its `catch (_)` in the
    // caller swallowed the result, so the cross-tenant write was silent.
    await _assertRowsInScope();
    final response = await _dio.post('$backendUrl/products/sync', data: {
      'products': [_productPayload(product)],
    });

    final synced = response.data['synced'] as List?;
    if (synced == null) return;
    for (final item in synced) {
      final remoteId = item['remoteId'];
      // A newly created product has no remote id until the server assigns one.
      if (remoteId is String && remoteId.isNotEmpty) {
        await DatabaseHelper.instance.setProductRemoteId(product.id!, remoteId);
      }
    }
  }

  /// Sync local products to backend (bulk upsert)
  static Future<void> syncProductsToBackend() async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) return;

    // Row-level scope, enforced before anything is posted. If the tenant this
    // shop is bound to now is not the one its `remote_id`s were minted under,
    // those ids are cleared rather than sent: they name rows in a namespace this
    // shop no longer belongs to.
    await _assertRowsInScope();

    final products =
        await DatabaseHelper.instance.getProducts(activeOnly: false);

    if (products.isEmpty) return;

    final response = await _dio.post('$backendUrl/products/sync', data: {
      'products': products.map(_productPayload).toList(),
    });

    // Update local DB with remote IDs in one transaction. This ran on the
    // 5-minute auto-sync path, so a per-row write meant one implicit
    // transaction and one fsync per product on every cycle.
    final synced = response.data['synced'] as List?;
    if (synced == null) return;
    final pairs = <int, String>{};
    for (final item in synced) {
      final localId = item['localId'];
      final remoteId = item['remoteId'];
      if (localId is int && remoteId is String && remoteId.isNotEmpty) {
        pairs[localId] = remoteId;
      }
    }
    if (pairs.isNotEmpty) {
      await DatabaseHelper.instance.setProductRemoteIds(pairs);
    }
  }

  /// Pushes the till's ledger to the server.
  ///
  /// ## WHY THIS EXISTS
  ///
  /// The till writes its sales OFFLINE, on the phone, and that is the whole
  /// point of it: a shop with no signal still sells, still takes the money and
  /// still knows what it sold.
  ///
  /// But the server had no way to learn about any of it. The only rows that
  /// ever reached the server were the M-Pesa ones — so CASH SALES, which are
  /// most of a shop's sales, never left the phone. The owner's account, the
  /// reports and the all-shops view were reading a ledger with holes in it.
  ///
  /// ## WHY IT IS SAFE TO PUSH THE SAME SALE TWICE
  ///
  /// A phone that was offline pushes the same sales again the next time it
  /// is online — that is the whole mechanism. The server keys each sale on
  /// the till's own id for it, so a re-push corrects the row it already has
  /// rather than making a second one, and a week's takings cannot become two
  /// weeks of takings.
  ///
  /// The local side keeps the same rule: a sale is marked pushed only when
  /// the server has confirmed it, so a sale the server did not accept is
  /// still pending and is tried again.
  static Future<void> syncSalesToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();

    final List<Sale> sales = await DatabaseHelper.instance.getUnsyncedSales();
    if (sales.isEmpty) return;

    final response = await _dio.post('$backendUrl/sales/sync', data: {
      'sales': sales.map(_salePayload).toList(),
    });

    final synced = response.data['synced'] as List?;
    if (synced == null) return;
    final List<int> confirmed = <int>[];
    for (final item in synced) {
      final localId = item['localId'];
      if (localId is int) confirmed.add(localId);
    }
    await DatabaseHelper.instance.markSalesSynced(confirmed);
  }

  /// One sale, in the shape the server reads.
  ///
  /// The MONEY IS IN MINOR UNITS — the integer cents the till counts in. The
  /// server's columns are major units and it converts once, on the way in; a
  /// float of shillings would lose a cent on the way and a ledger that is a
  /// cent out is a ledger that does not reconcile against the drawer.
  static Map<String, dynamic> _salePayload(Sale sale) => {
        'localId': sale.id,
        'staffName': sale.staffName,
        'paymentMethod': sale.paymentMethod,
        'paymentReference': sale.paymentReference,
        'total': sale.total.minorUnits,
        'profit': sale.profit.minorUnits,
        'amountTendered': sale.amountTendered.minorUnits,
        'changeGiven': sale.changeGiven.minorUnits,
        'createdAt': sale.createdAt,
        'items': sale.items
            .map((SaleItem item) => <String, dynamic>{
                  'productId': item.productId,
                  'productName': item.productName,
                  'qty': item.qty,
                  'unitPrice': item.unitPrice.minorUnits,
                  'unitCost': item.unitCost.minorUnits,
                  'portion': item.portion,
                  'portionMl': item.portionMl,
                })
            .toList(),
      };

  /// Pushes the till's drawers to the server.
  ///
  /// A shift is opened OFFLINE — a shop with one device and its staff on it
  /// has no signal half the time, and a shift that needs a server is a shift
  /// nobody opens — and the shift is pushed when the phone can reach it.
  static Future<void> syncShiftsToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();

    final List<Map<String, dynamic>> shifts =
        await DatabaseHelper.instance.getUnsyncedShifts();
    if (shifts.isEmpty) return;

    final response = await _dio.post('$backendUrl/shifts/sync', data: {
      'shifts': shifts
          .map((Map<String, dynamic> shift) => <String, dynamic>{
                'localId': shift['id'],
                'staffName': shift['staff_name'],
                'startTime': shift['start_time'],
                'endTime': shift['end_time'],
                'startFloat': shift['start_float'] ?? 0,
                'endFloat': shift['end_float'] ?? 0,
                'expectedCash': shift['expected_cash'] ?? 0,
                'countedCash': shift['counted_cash'] ?? 0,
                'status': shift['status'] ?? 'open',
              })
          .toList(),
    });

    final synced = response.data['synced'] as List?;
    if (synced == null) return;
    final List<int> confirmed = <int>[];
    for (final item in synced) {
      final localId = item['localId'];
      if (localId is int) confirmed.add(localId);
    }
    await DatabaseHelper.instance.markShiftsSynced(confirmed);
  }

  /// Pushes the till's shot cups to the server.
  ///
  /// A shot cup is set up ONCE, on one phone, and it is the whole shop's
  /// shelf after that: a cup the owner set up in the office has to be the cup
  /// the counter sells from.
  static Future<void> syncShotCupsToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();

    final List<ShotCup> cups =
        await DatabaseHelper.instance.getUnsyncedShotCups();
    if (cups.isEmpty) return;

    final response = await _dio.post('$backendUrl/shot-cups/sync', data: {
      'shotCups': cups
          .map((ShotCup cup) => <String, dynamic>{
                'localId': cup.id,
                'productId': cup.productId,
                'productName': cup.productName,
                'label': cup.label,
                // Zero means the size is not known, and that is a legal
                // answer: a cup with a size earns its cost exactly, and a cup
                // without one is counted at its full price.
                'capacityMl': cup.capacityMl,
                'price': cup.price.minorUnits,
                'active': cup.active,
              })
          .toList(),
    });

    final synced = response.data['synced'] as List?;
    if (synced == null) return;
    final List<int> confirmed = <int>[];
    for (final item in synced) {
      final localId = item['localId'];
      if (localId is int) confirmed.add(localId);
    }
    await DatabaseHelper.instance.markShotCupsSynced(confirmed);
  }

  /// Pushes the till's returns to the server.
  ///
  /// A return is the one thing in a till that gives money back, so the server
  /// has to hear about it: a credit note the tax authority never saw is a
  /// credit note that does not exist, and a return the owner cannot see on
  /// another device is a return the books disagree about.
  ///
  /// The push is keyed on the till's own id for the return, so a phone that
  /// was offline pushes the same return again without refunding it twice.
  static Future<void> syncReturnsToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();

    final List<SaleReturn> returns =
        await DatabaseHelper.instance.getUnsyncedReturns();
    if (returns.isEmpty) return;

    // ONE AT A TIME.
    //
    // The server takes a return on its own, and a shop's returns are rare —
    // a handful in a week, on a bad day. One request each keeps the contract
    // simple, and it means one refused return does not hold up the rest: each
    // is sent on its own, and only the ones the server confirmed are marked.
    final List<int> confirmed = <int>[];
    for (final SaleReturn entry in returns) {
      try {
        final response = await _dio.post('$backendUrl/returns', data: {
          'localId': entry.id,
          'originalSaleLocalId': entry.saleId,
          'kind': entry.kind,
          'reason': entry.reason,
          'total': entry.total.minorUnits,
          'profit': entry.profit.minorUnits,
          'staffName': entry.staffName,
          'createdAt': entry.createdAt,
          'items': entry.items
              .map((SaleReturnItem item) => <String, dynamic>{
                    'productId': item.productId,
                    'productName': item.productName,
                    'qty': item.qty,
                    'unitPrice': item.unitPrice.minorUnits,
                    'unitCost': item.unitCost.minorUnits,
                    'portion': item.portion,
                    'portionMl': item.portionMl,
                  })
              .toList(),
        });
        final returned = response.data['localId'];
        if (returned is int) {
          confirmed.add(returned);
        }
      } on DioException catch (error) {
        // One refused return must not hold up the rest, and the return that
        // failed stays pending so the next push tries it again.
        debugPrint('Return push failed for ${entry.id}: $error');
      }
    }
    await DatabaseHelper.instance.markReturnsSynced(confirmed);
  }

  /// Pushes the till's deliveries to the server.
  ///
  /// A delivery is the shop's record of what it paid for its stock, and the
  /// cost on those goods is what every later sale's profit is measured
  /// against. A delivery the server has not seen is a delivery the other
  /// devices do not know about.
  ///
  /// The push is keyed on the till's own id for the delivery, so a phone that
  /// was offline pushes the same delivery again without doubling the stock.
  static Future<void> syncReceiptsToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();

    final List<StockReceipt> receipts =
        await DatabaseHelper.instance.getUnsyncedReceipts();
    if (receipts.isEmpty) return;

    final List<int> confirmed = <int>[];
    for (final StockReceipt receipt in receipts) {
      try {
        final response = await _dio.post('$backendUrl/purchases', data: {
          'localId': receipt.id,
          'supplierName': receipt.supplierRef ?? '',
          'invoiceNumber': receipt.supplierRef,
          'total': receipt.totalCost.minorUnits,
          'staffName': receipt.staffName,
          'createdAt': receipt.receivedAt,
          'items': receipt.items
              .map((StockReceiptItem item) => <String, dynamic>{
                    'productId': item.productId,
                    'productName': item.productName,
                    'qty': item.qty,
                    'unitCost': item.unitCost.minorUnits,
                  })
              .toList(),
        });
        final returned = response.data['localId'];
        if (returned is int) {
          confirmed.add(returned);
        }
      } on DioException catch (error) {
        // One refused delivery must not hold up the rest, and the one that
        // failed stays pending so the next push tries it again.
        debugPrint('Delivery push failed for ${receipt.id}: $error');
      }
    }
    await DatabaseHelper.instance.markReceiptsSynced(confirmed);
  }

  static Future<void> syncStaffToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    // Same scope rule as the product sync: a tombstoned cashier whose
    // `remote_id` was minted under another tenant must not be replayed.
    await _assertRowsInScope();
    final tombstones =
        await DatabaseHelper.instance.getStaffDeletionTombstones();
    for (final tombstone in tombstones) {
      final remoteId = tombstone['remote_id'];
      final localId = tombstone['staff_id'];
      if (remoteId is String && localId is int) {
        try {
          await _dio.delete('$backendUrl/tenant/staff/$remoteId',
              data: {'reason': 'Cashier deletion requested on till'});
        } on DioException catch (error) {
          if (error.response?.statusCode != 404) {
            // ignore: avoid_print
            print('Staff tombstone deletion failed for $remoteId: $error');
            continue;
          }
        }
        await DatabaseHelper.instance.clearStaffDeletionTombstone(localId);
      } else if (localId is int) {
        await DatabaseHelper.instance.clearStaffDeletionTombstone(localId);
      }
    }
    final deletedIds =
        tombstones.map((row) => row['staff_id']).whereType<int>().toSet();
    final staff = (await DatabaseHelper.instance.getStaff(activeOnly: false))
        .where((s) => s.id == null || !deletedIds.contains(s.id))
        .toList();
    final response = await _dio.post('$backendUrl/tenant/staff/sync', data: {
      'staff': staff
          .map((s) => {
                'localId': s.id,
                'remoteId': s.remoteId,
                'name': s.name,
                'role': s.role,
                'active': s.active,
              })
          .toList(),
    });
    final synced = response.data['synced'] as List?;
    if (synced == null) return;
    for (final item in synced) {
      final localId = item['localId'];
      final remoteId = item['remoteId'];
      if (localId is int && remoteId is String) {
        await DatabaseHelper.instance.setStaffRemoteId(localId, remoteId);
      }
    }
  }

  /// Initiate M-Pesa STK push payment
  static Future<String> initiatePayment({
    required List<Map<String, dynamic>> items,
    required String phoneNumber,
    required String staffName,
    String? customerName,
    String? staffProfileId,
  }) async {
    await ensureInitialized();

    final result = await _dio.post('$backendUrl/payments/initiate', data: {
      'items': items,
      'phone_number': phoneNumber,
      'staff_name': staffName,
      if (staffProfileId != null) 'staff_profile_id': staffProfileId,
      if (customerName != null) 'customer_name': customerName,
    });

    final reference = result.data['reference'];
    if (reference == null) {
      throw StateError('No payment reference returned');
    }

    return reference as String;
  }

  /// Poll payment status until resolved or timeout
  static Future<PaymentOutcome> pollPaymentStatus(
    String reference, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    await ensureInitialized();
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      try {
        final result = await _dio.get(
          '$backendUrl/payments/status',
          queryParameters: {'reference': reference},
        );

        final status = result.data['status'];
        if (status == 'SUCCESS') return PaymentOutcome.success;
        if (status == 'FAILED') return PaymentOutcome.failed;

        await Future.delayed(const Duration(seconds: 3));
      } catch (e) {
        // Continue polling on network errors
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    return PaymentOutcome.timedOut;
  }
}

enum PaymentOutcome { success, failed, timedOut }

/// What the backend returned for an issued tax receipt.
class EtimsIssueResult {
  const EtimsIssueResult({
    required this.kraReceiptNumber,
    this.verificationUrl,
    this.qrPayload,
  });

  /// KRA's own receipt number. This is the number an auditor asks for, and it
  /// is *not* the till's own `receipt_number` — the two are deliberately
  /// independent so a KRA-side gap cannot renumber what the customer was
  /// already handed.
  final String kraReceiptNumber;

  /// The page a customer scans to verify the receipt against KRA.
  final String? verificationUrl;

  /// The exact string encoded in the receipt's QR code.
  ///
  /// Preferred over [verificationUrl] for the QR because KRA's verification
  /// page expects specific parameters; encoding a URL built locally is how a
  /// receipt ends up with a QR that scans to a 404.
  final String? qrPayload;
}

/// The shop's eTIMS posture, for the settings screen.
class EtimsQueueStatus {
  const EtimsQueueStatus({
    required this.configured,
    required this.pending,
    required this.rejected,
    this.deviceStatus,
    this.tin,
  });

  /// Whether the shop has a TIN and a registered device, without which no
  /// receipt can be issued at all.
  final bool configured;

  final int pending;
  final int rejected;
  final String? deviceStatus;
  final String? tin;
}
