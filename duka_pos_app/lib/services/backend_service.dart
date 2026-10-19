import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
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
    required this.accessToken,
    required this.refreshToken,
    required this.expiresInSeconds,
  });

  factory VerifiedIdentity.fromJson(Map<String, dynamic> json) =>
      VerifiedIdentity(
        tenantId: json['tenant_id'] as String? ?? '',
        shopName: json['shop_name'] as String? ?? '',
        accessToken: json['access_token'] as String? ?? '',
        refreshToken: json['refresh_token'] as String? ?? '',
        expiresInSeconds: (json['expires_in_seconds'] as num?)?.toInt() ?? 0,
      );

  final String tenantId;
  final String shopName;
  final String accessToken;
  final String refreshToken;
  final int expiresInSeconds;
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

  /// A second client with no interceptors, for the one call that must not
  /// recurse into them: refreshing a session is what a 401 handler does, and
  /// doing that through the interceptor that retries on 401 is a loop.
  static final Dio _unauthenticated = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));
  static SharedPreferences? _prefs;

  /// Marks a request that has already had one chance to renew its session.
  static const String _authRetriedKey = 'auth_retried';

  static const backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://localhost:3000/api',
  );

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
        // The browser session first, then the device-linked one. A shop that
        // signed in through Keycloak keeps using that token; a shop that
        // tapped Verify and typed a mailed code uses the session the backend
        // minted for it. Both are bearer tokens to this interceptor.
        final token = await OidcService.accessToken ??
            await OidcService.appSessionAccessToken;
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

          // A device session can be renewed without a browser, so try that
          // before falling back to clearing tokens and asking the owner to
          // sign in.
          if (await OidcService.hasAppSession && await _refreshAppSession()) {
            final refreshed = await OidcService.appSessionAccessToken;
            if (refreshed != null) {
              requestOptions.headers['Authorization'] = 'Bearer $refreshed';
              try {
                return handler.resolve(await _dio.fetch(requestOptions));
              } on DioException catch (_) {
                return handler.next(error);
              }
            }
          }
          await OidcService.clearAccessToken();
          final newToken = await OidcService.accessToken;
          if (newToken != null) {
            requestOptions.headers['Authorization'] = 'Bearer $newToken';
            try {
              return handler.resolve(await _dio.fetch(requestOptions));
            } on DioException catch (_) {
              return handler.next(error);
            }
          }
          await OidcService.logout();
        }
        return handler.next(error);
      },
    ));

    _initialized = true;
  }

  /// Exchanges the stored refresh token for a new session.
  ///
  /// Returns false for every failure — no signal, an expired token, a server
  /// that says no — because every one of them means the same thing to the
  /// caller: this session is finished.
  static Future<bool> _refreshAppSession() async {
    final refreshToken = await OidcService.appSessionRefreshToken;
    if (refreshToken == null) return false;
    try {
      final response = await _unauthenticated.post(
        '$backendUrl/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final identity = VerifiedIdentity.fromJson(
          response.data as Map<String, dynamic>? ?? const {});
      await _adoptVerifiedIdentity(identity);
      return true;
    } on DioException catch (_) {
      await OidcService.clearAppSession();
      return false;
    } catch (_) {
      await OidcService.clearAppSession();
      return false;
    }
  }

  /// Stores a freshly minted session and points the till at its shop.
  ///
  /// Shared by verify and refresh so the two paths cannot disagree about where
  /// the token lives or which workspace the shop maps to.
  static Future<void> _adoptVerifiedIdentity(VerifiedIdentity identity) async {
    if (identity.accessToken.isEmpty) {
      throw StateError('The backend returned no session');
    }
    await OidcService.storeAppSession(
      accessToken: identity.accessToken,
      refreshToken: identity.refreshToken,
      expiresAt:
          DateTime.now().add(Duration(seconds: identity.expiresInSeconds)),
    );
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
  /// The [pin] is the shop's own 4-digit admin PIN, and it is verified against
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
  /// On success this also stores the session the backend minted and points the
  /// till at its tenant, which is what unlocks auto-backups, analytics and
  /// auto-update — they all read the linked shop from the same session.
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
  static Future<bool> adjustStockOnBackend({
    required Product product,
    required int delta,
    String? reason,
    String? staffProfileId,
  }) async {
    await ensureInitialized();
    final tid = await tenantId;
    if (tid == null) return false;
    final remoteId = product.remoteId;
    if (remoteId == null) return false;
    // The remote id names a row in one tenant's namespace. If the shop has been
    // relinked since that id was minted, the write would land on a foreign row,
    // so the scope is checked rather than assumed.
    await _assertRowsInScope();
    try {
      await _dio.post('$backendUrl/products/stock-adjust', data: {
        'product_id': remoteId,
        'delta': delta,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (staffProfileId != null) 'staff_profile_id': staffProfileId,
      });
      return true;
    } on DioException {
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
