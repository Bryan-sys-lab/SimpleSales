import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import '../models/stock_movement.dart';
import '../models/session_renewal.dart';
import 'etims/etims_service.dart';
import 'encrypted_backup_service.dart';
import 'oidc_service.dart';
import 'row_scope.dart';
import 'workspace_service.dart';
import 'portfolio_kpis.dart';
import 'cross_shop_activity.dart';
import 'analytics.dart';
import '../models/incoming_payment.dart';
import '../models/tax_entity.dart';
import '../utils/money.dart';
import '../utils/crypto_utils.dart';
import '../profile/shop_profile.dart';

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
  static const String defaultBackendUrl = 'https://duka-pos-backend.brianbmk332.workers.dev/api';

  static const backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://duka-pos-backend.brianbmk332.workers.dev/api',
  );

  /// Why this build may not reach a server, or null when it may.
  ///
  /// Pure, and separate from the rest of the service, because the constant
  /// [backendUrl] is fixed at compile time: a test cannot change it, so the
  /// RULE has to be testable on its own.
  ///
  /// A debug build is never a problem — the
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
        // The normal mobile credential is the Keycloak access token. The
        // backend also accepts its short-lived email-code session for API
        // clients that complete verification without Keycloak.
        final token = await OidcService.accessToken;
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        // The tenant this shop on this device maps to, NOT a global preference.
        //
        // A device can hold several shops, and each has its own tenant: reading
        // the active tenant from the registry means the second shop's requests
        // are sent under the second shop's tenant instead of whichever shop
        // verified most recently. An unlinked shop sends no tenant header at all
        // rather than borrowing a neighbour's.
        final explicitTenant = options.extra['staffTenantOverride'];
        final selectedTenant =
            explicitTenant is String && explicitTenant.isNotEmpty
                ? explicitTenant
                : await WorkspaceService.activeTenantId();
        if (selectedTenant != null) {
          options.headers['x-tenant-id'] = selectedTenant;
        }
        if (options.extra['binaryUpload'] != true) {
          options.headers['Content-Type'] = 'application/json';
        }
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
  /// The verification response identifies the shop and the till then signs in
  /// to Keycloak for its normal API credential. The backend's opaque
  /// verification session remains available to non-Keycloak clients.
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
  /// signs in to Keycloak for the normal mobile credential. The backend's
  /// opaque verification session remains available to non-Keycloak clients.
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

  static const _syncDeviceIdKey = 'sync_device_id';

  /// Stable per-install identity used to namespace local integer ids on the
  /// backend. It is intentionally not a staff or owner identifier: several
  /// staff members can use one till, and one owner can have several tills.
  static Future<String> _syncDeviceId() async {
    final prefs = await _prefsInstance;
    final existing = prefs.getString(_syncDeviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = generateUuid();
    await prefs.setString(_syncDeviceIdKey, created);
    return created;
  }

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

  /// Creates a public receipt page from an immutable receipt snapshot.
  /// Returns null when the backend is unavailable; the caller can still share
  /// the same receipt as text while offline.
  static Future<Map<String, dynamic>?> createReceiptLink(
      Map<String, dynamic> snapshot) async {
    await ensureInitialized();
    try {
      final response = await _dio.post('$backendUrl/receipt-links',
          data: <String, dynamic>{'snapshot': snapshot});
      final data = response.data;
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on DioException catch (_) {
      return null;
    }
  }

  static Future<bool> revokeReceiptLink(String token) async {
    await ensureInitialized();
    try {
      final response = await _dio.delete('$backendUrl/receipt-links/$token');
      return response.statusCode == null ||
          (response.statusCode! >= 200 && response.statusCode! < 300);
    } on DioException catch (_) {
      return false;
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
  /// Returns true when the server accepted the code. The caller writes the new
  /// hash locally, and the NEW PIN goes with the request because the identity
  /// server's password IS the admin PIN: a reset that changed only the phone's
  /// copy would leave the account expecting the PIN the owner had forgotten,
  /// and the next cloud sign-in would fail with the credential this screen had
  /// just handed them.
  static Future<bool> confirmPinReset({
    required String email,
    required String challengeId,
    required String code,
    required String newPin,
  }) async {
    await ensureInitialized();
    try {
      final response =
          await _dio.post('$backendUrl/auth/pin-reset/confirm', data: {
        'email': email.trim(),
        'challengeId': challengeId,
        'code': code.trim(),
        'newPin': newPin,
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

  /// Uploads the already-compressed local avatar to object storage. The
  /// profile row receives only the returned URL; image bytes never enter
  /// PostgreSQL or a backup payload. A presigned URL keeps the binary off the
  /// API request path while the confirm call binds the object to this user.
  static Future<String> uploadProfilePhoto(File file) async {
    await ensureInitialized();
    final String fileName = file.path.split(Platform.pathSeparator).last;
    final uploadResponse = await _dio.post<Map<String, dynamic>>(
      '$backendUrl/profile/photo/upload-url',
      data: <String, dynamic>{
        'fileName': fileName,
        'contentType': 'image/jpeg',
      },
    );
    final uploadData = uploadResponse.data ?? const <String, dynamic>{};
    final String? uploadUrl = uploadData['uploadUrl'] as String?;
    final String? key = uploadData['key'] as String?;
    if (uploadUrl == null || key == null || uploadUrl.isEmpty || key.isEmpty) {
      throw StateError('Profile photo upload was not prepared');
    }
    await _dio.put<void>(
      uploadUrl,
      data: await file.readAsBytes(),
      options: Options(
        contentType: 'image/jpeg',
        extra: <String, dynamic>{'binaryUpload': true},
      ),
    );
    final confirmResponse = await _dio.post<Map<String, dynamic>>(
      '$backendUrl/profile/photo/confirm',
      data: <String, dynamic>{'key': key},
    );
    final String? photoUrl = confirmResponse.data?['photoUrl'] as String?;
    if (photoUrl == null || photoUrl.isEmpty) {
      throw StateError('Profile photo was uploaded without a stored link');
    }
    return photoUrl;
  }

  /// Cloud features are enabled only after this workspace completed the
  /// email-verification handshake. A stale tenant link must not silently turn
  /// cloud backup back on for a shop that was relinked or restored offline.
  static Future<bool> get isIdentityVerified async {
    final workspace = await WorkspaceService.activeWorkspaceKey();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('profile_email_verified@$workspace') ?? false;
  }

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

  static Future<CrossShopActivityPage> crossShopActivity({
    required DateTime from,
    required DateTime to,
    String? tenantId,
    String? profile,
    String? payment,
    String? type,
    String? status,
    String? cursor,
    int limit = 100,
  }) async {
    await ensureInitialized();
    final response = await _dio.get<Map<String, dynamic>>(
      '$backendUrl/tenant/activity',
      queryParameters: <String, String>{
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
        'limit': '$limit',
        if (tenantId != null) 'tenantId': tenantId,
        if (profile != null) 'profile': profile,
        if (payment != null) 'payment': payment,
        if (type != null) 'type': type,
        if (status != null) 'status': status,
        if (cursor != null) 'cursor': cursor,
      },
    );
    return CrossShopActivityPage.fromJson(response.data ?? const {});
  }

  /// Reads only bounded aggregates for a linked shop whose local ledger is
  /// empty. The app never downloads the full remote sales history just to draw
  /// KPI cards; offline/local analytics remain the normal path.
  static Future<RemoteSalesSummary> remoteSalesSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    await ensureInitialized();
    final response = await _dio.get<Map<String, dynamic>>(
      '$backendUrl/reports/sales',
      queryParameters: <String, String>{
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
        'limit': '1',
      },
    );
    return RemoteSalesSummary.fromJson(
        response.data ?? const <String, dynamic>{});
  }

  static Future<RemoteProductReport> remoteProductReport({
    required DateTime from,
    required DateTime to,
    String? productId,
  }) async {
    await ensureInitialized();
    final response = await _dio.get<Map<String, dynamic>>(
      '$backendUrl/reports/products',
      queryParameters: <String, String>{
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
        if (productId != null) 'productId': productId,
      },
    );
    return RemoteProductReport.fromJson(
        response.data ?? const <String, dynamic>{});
  }

  static Future<Map<String, dynamic>> remoteSaleDetails(String saleId) async {
    await ensureInitialized();
    final response = await _dio.get<Map<String, dynamic>>(
      '$backendUrl/reports/sales/${Uri.encodeComponent(saleId)}',
    );
    return response.data ?? const <String, dynamic>{};
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
    String? tenantId,
  }) async {
    await ensureInitialized();
    try {
      final response = await _dio.post('$backendUrl/tenant/staff/authenticate',
          data: {'username': username, 'pin': pin},
          options: tenantId == null || tenantId.trim().isEmpty
              ? null
              : Options(
                  extra: <String, Object>{'staffTenantOverride': tenantId},
                  headers: <String, String>{'x-tenant-id': tenantId},
                ));
      final data = response.data as Map<String, dynamic>? ?? const {};
      return data.isNotEmpty ? data : null;
    } on DioException catch (error) {
      // A reachable backend that rejected the credentials is authoritative:
      // do not silently turn an online deactivation or wrong PIN into an
      // offline login. Only transport failures and 5xx responses may use the
      // local roster as an offline fallback.
      final status = error.response?.statusCode;
      if (status != null && status < 500) {
        return const <String, dynamic>{'_rejected': true};
      }
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
        data: {'mpesaEnabled': true, 'payheroChannelId': channelId});
  }

  /// One-time backend registration after the owner completes OIDC login.
  static Future<void> linkShopToBackend({
    required String shopName,
    required String ownerName,
    String email = '',
    ShopProfile businessProfile = ShopProfile.duka,
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
        'businessProfile': businessProfile.wireValue,
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
      if (channelId != null) 'payheroChannelId': channelId,
    });
  }

  /// Registers the shop's own Till or Paybill through the platform's
  /// server-side PayHero account. No PayHero credential is accepted by the
  /// mobile app.
  static Future<int> registerMpesaChannel({
    required String channelType,
    required String shortCode,
  }) async {
    await ensureInitialized();
    if (await tenantId == null) {
      throw StateError('Shop is not linked to backend');
    }
    final response = await _dio
        .post('$backendUrl/tenant/mpesa/channel', data: <String, dynamic>{
      'channelType': channelType.toLowerCase(),
      'shortCode': shortCode,
    });
    final id = response.data is Map ? response.data['channelId'] : null;
    if (id is! int || id <= 0) {
      throw StateError('PayHero did not return a payment channel');
    }
    return id;
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

  static Future<TaxEntitySnapshot?> fetchTaxEntity() async {
    await ensureInitialized();
    if (await tenantId == null) return null;
    try {
      final response = await _dio.get('$backendUrl/tenant/tax-entity');
      if (response.data is! Map || response.data['tax_entity'] == null) {
        return null;
      }
      final snapshot = TaxEntitySnapshot.fromResponse(
        Map<String, dynamic>.from(response.data as Map),
      );
      try {
        final returnResponse =
            await _dio.get('$backendUrl/tenant/tax-entity/vat-return');
        final returnJson = returnResponse.data is Map
            ? (returnResponse.data as Map)['vat_return']
            : null;
        if (returnJson is Map) {
          final merged = Map<String, dynamic>.from(response.data as Map);
          merged['vat_return'] = Map<String, dynamic>.from(returnJson);
          final snapshotWithVat = TaxEntitySnapshot.fromResponse(merged);
          try {
            final totResponse =
                await _dio.get('$backendUrl/tenant/tax-entity/tot-return');
            final totJson = totResponse.data is Map
                ? (totResponse.data as Map)['tot_return']
                : null;
            if (totJson is Map) {
              merged['tot_return'] = Map<String, dynamic>.from(totJson);
              return await _cacheTaxRuleAndReturn(
                  TaxEntitySnapshot.fromResponse(merged));
            }
          } on DioException catch (_) {}
          return await _cacheTaxRuleAndReturn(snapshotWithVat);
        }
      } on DioException catch (_) {
        // The tax entity itself remains usable when no period return exists.
      }
      try {
        final totResponse =
            await _dio.get('$backendUrl/tenant/tax-entity/tot-return');
        final totJson = totResponse.data is Map
            ? (totResponse.data as Map)['tot_return']
            : null;
        if (totJson is Map) {
          final merged = Map<String, dynamic>.from(response.data as Map);
          merged['tot_return'] = Map<String, dynamic>.from(totJson);
          return await _cacheTaxRuleAndReturn(
              TaxEntitySnapshot.fromResponse(merged));
        }
      } on DioException catch (_) {}
      return await _cacheTaxRuleAndReturn(snapshot);
    } on DioException catch (_) {
      return null;
    }
  }

  static Future<TaxEntitySnapshot> _cacheTaxRuleAndReturn(
      TaxEntitySnapshot snapshot) async {
    final rule = snapshot.currentVatRule;
    if (rule != null) {
      await DatabaseHelper.instance
          .setSetting(DatabaseHelper.settingTaxRuleId, rule.id);
      await DatabaseHelper.instance
          .setSetting(DatabaseHelper.settingTaxRuleVersion, '${rule.version}');
    } else {
      await DatabaseHelper.instance
          .setSetting(DatabaseHelper.settingTaxRuleId, null);
      await DatabaseHelper.instance
          .setSetting(DatabaseHelper.settingTaxRuleVersion, null);
    }
    return snapshot;
  }

  static Future<TaxEntitySnapshot?> saveTaxEntity({
    required String legalForm,
    required String displayLabel,
    required List<String> obligations,
    required int accountingPeriodStartMonth,
    required String status,
    required DateTime effectiveFrom,
    String etimsOnboardingStatus = 'not_started',
    String? etimsMethod,
    String? outletReference,
    String? kraPin,
  }) async {
    await ensureInitialized();
    if (await tenantId == null) {
      throw StateError('Shop is not linked to backend');
    }
    await _dio.patch('$backendUrl/tenant/tax-entity', data: {
      'legalForm': legalForm,
      'displayLabel': displayLabel,
      'registeredTaxObligations': obligations,
      'accountingPeriodStartMonth': accountingPeriodStartMonth,
      'status': status,
      'etimsOnboardingStatus': etimsOnboardingStatus,
      if (etimsMethod != null) 'etimsMethod': etimsMethod,
      'effectiveFrom': effectiveFrom.toUtc().toIso8601String(),
      if (outletReference != null) 'outletReference': outletReference,
      if (kraPin != null && kraPin.isNotEmpty) 'kraPin': kraPin,
    });
    return fetchTaxEntity();
  }

  /// Persists an intentional profile change for the currently linked shop.
  /// Offline profile state remains authoritative until the next successful
  /// retry; the caller may safely ignore transport failures.
  static Future<void> setBusinessProfile(ShopProfile profile) async {
    await ensureInitialized();
    if (await tenantId == null) {
      throw StateError('Shop is not linked to backend');
    }
    await _dio.patch('$backendUrl/tenant/settings', data: {
      'businessProfile': profile.wireValue,
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
    required num delta,
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
  static Map<String, dynamic> _productPayload(Product product,
          {double? openingStockQty, String? syncKey}) =>
      {
        'id': product.id,
        'remoteId': product.remoteId,
        if (syncKey != null) 'syncKey': syncKey,
        'name': product.name,
        'category': product.category,
        'costPrice': product.costPrice.asMajor,
        'sellPrice': product.sellPrice.asMajor,
        'stockQty': product.stockQty,
        if (openingStockQty != null) 'openingStockQty': openingStockQty,
        'reorderLevel': product.reorderLevel,
        'bottleMl': product.bottleMl,
        'unit': product.unit.wire,
        'mlPerKg': product.millilitresPerKilogram,
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
    final deviceId = await _syncDeviceId();
    final openingStockQty = product.remoteId == null
        ? await DatabaseHelper.instance.openingStockQtyForProduct(product.id!)
        : null;
    final response = await _dio.post('$backendUrl/products/sync', data: {
      'products': [
        _productPayload(
          product,
          openingStockQty: openingStockQty,
          syncKey: product.id == null ? null : '$deviceId:${product.id}',
        ),
      ],
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

    final deviceId = await _syncDeviceId();
    // Keep requests bounded for a catalogue that was edited while a till was
    // offline for months. Earlier batches are committed locally immediately;
    // if a later request fails, the next cycle resumes with only that suffix.
    const batchSize = 200;
    for (var start = 0; start < products.length; start += batchSize) {
      final batch = products.skip(start).take(batchSize);
      final payloads = <Map<String, dynamic>>[];
      for (final product in batch) {
        final openingStockQty = product.remoteId == null && product.id != null
            ? await DatabaseHelper.instance
                .openingStockQtyForProduct(product.id!)
            : null;
        payloads.add(_productPayload(
          product,
          openingStockQty: openingStockQty,
          syncKey: product.id == null ? null : '$deviceId:${product.id}',
        ));
      }
      final response = await _dio.post('$backendUrl/products/sync', data: {
        'products': payloads,
      });

      // Update local DB in one transaction per batch. This keeps each retry
      // idempotent without turning a large catalogue sync into one enormous
      // request or one write transaction.
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
  }

  /// Pulls catalogue and stock changes made by another device in this tenant.
  /// Upload runs first in the automatic cycle, so this cannot overwrite a
  /// local product that has not yet been offered to the server.
  static Future<void> pullProductsFromBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();
    final localProducts =
        await DatabaseHelper.instance.getProducts(activeOnly: false);
    final localByRemoteId = <String, Product>{
      for (final product in localProducts)
        if (product.remoteId != null) product.remoteId!: product,
    };
    var offset = 0;
    while (true) {
      final response = await _dio.get('$backendUrl/products', queryParameters: {
        'limit': 200,
        'offset': offset,
      });
      final data = response.data;
      // Accept the old list response during a rolling deployment, while new
      // servers return bounded pages with an explicit continuation offset.
      final rows = data is List
          ? data
          : data is Map && data['products'] is List
              ? data['products'] as List
              : const <dynamic>[];
      for (final raw in rows.whereType<Map>()) {
        final remoteId = raw['id'];
        if (remoteId is! String || remoteId.isEmpty) continue;
        final localProduct = localByRemoteId[remoteId];
        final unsyncedStockDelta = localProduct?.id == null
            ? 0.0
            : await DatabaseHelper.instance
                .unsyncedStockDeltaForProduct(localProduct!.id!);
        await DatabaseHelper.instance.mergeRemoteProduct(
          remoteId: remoteId,
          name: raw['name'] as String? ?? 'Unnamed product',
          category: raw['category'] as String? ?? 'General',
          costPriceMinor: Money.fromMajor(raw['costPrice'] ?? 0).minorUnits,
          sellPriceMinor: Money.fromMajor(raw['sellPrice'] ?? 0).minorUnits,
          stockQty: (raw['stockQty'] as num?)?.toDouble() ??
              double.tryParse('${raw['stockQty'] ?? 0}') ??
              0,
          reorderLevel: (raw['reorderLevel'] as num?)?.toInt() ?? 0,
          bottleMl: (raw['bottleMl'] as num?)?.toInt() ?? 750,
          unit: raw['unit'] as String? ?? 'each',
          millilitresPerKilogram: raw['mlPerKg'] is num
              ? (raw['mlPerKg'] as num).toDouble()
              : double.tryParse('${raw['mlPerKg'] ?? 0}') ?? 0,
          halfPriceMinor: raw['halfPrice'] == null
              ? null
              : Money.fromMajor(raw['halfPrice']).minorUnits,
          quarterPriceMinor: raw['quarterPrice'] == null
              ? null
              : Money.fromMajor(raw['quarterPrice']).minorUnits,
          exciseStampBatch: raw['exciseStampBatch'] as String? ?? '',
          active: raw['active'] == true,
          unsyncedStockDelta: unsyncedStockDelta,
        );
      }
      if (data is! Map || data['nextOffset'] is! num) break;
      offset = (data['nextOffset'] as num).toInt();
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

    // The server accepts bounded batches. Drain the backlog in one online
    // session so a shop that was offline for months does not wait another six
    // hours between every 500-sale page. Stop when a page makes no progress;
    // that leaves genuine stock conflicts queued for owner review rather than
    // spinning forever.
    final Map<int, String> remotes = await _productRemoteIds();
    final deviceId = await _syncDeviceId();
    while (true) {
      final List<Sale> sales = await DatabaseHelper.instance.getUnsyncedSales();
      if (sales.isEmpty) return;
      final payloads = <Map<String, dynamic>>[];
      for (final Sale sale in sales) {
        final tenders = sale.id == null
            ? const <SalePayment>[]
            : await DatabaseHelper.instance.getSalePayments(sale.id!);
        payloads.add(_salePayload(sale, remotes, deviceId, tenders));
      }
      final response = await _dio.post('$backendUrl/sales/sync', data: {
        'sales': payloads,
      });

      final synced = response.data['synced'] as List?;
      if (synced == null) return;
      final List<int> confirmed = <int>[];
      for (final item in synced) {
        final localId = item['localId'];
        if (localId is int) confirmed.add(localId);
      }
      await DatabaseHelper.instance.markSalesSynced(confirmed);
      final conflicts = response.data['conflicts'] as List?;
      if (conflicts != null && conflicts.isNotEmpty) {
        for (final raw in conflicts.whereType<Map>()) {
          final localId = raw['localId'];
          if (localId is! int) continue;
          final payload = payloads.firstWhere(
            (item) => item['localId'] == localId,
            orElse: () => <String, dynamic>{},
          );
          await DatabaseHelper.instance.recordSyncConflict(
            uuid: '$deviceId:$localId',
            kind: 'sale_stock',
            localId: localId,
            deviceId: deviceId,
            reason: raw['reason'] as String? ?? 'Sale needs stock review',
            payloadJson: payload.isEmpty ? null : jsonEncode(payload),
          );
        }
        debugPrint('Sales held for stock review: ${conflicts.length}');
      }
      if (confirmed.isEmpty || sales.length < 500) return;
    }
  }

  /// Uploads only sanitized financial evidence. Customer, product-display and
  /// free-form fields remain in the owner operational copy or locally.
  static Future<void> syncFinancialEvidenceToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    final events =
        await DatabaseHelper.instance.getUnsyncedFinancialEvents(limit: 500);
    if (events.isEmpty) return;
    final deviceId = await _syncDeviceId();
    final response = await _dio.post('$backendUrl/evidence/sync', data: {
      'deviceId': deviceId,
      'events': events
          .where((event) => event.id != null)
          .map((event) => {
                'localId': event.id,
                'uuid': event.uuid,
                'eventType': event.eventType,
                'sourceType': event.sourceType,
                'sourceId': event.sourceId,
                'occurredAtUtc': event.occurredAtUtc,
                'revenueMinor': event.revenueMinor,
                'cashInMinor': event.cashInMinor,
                'cashOutMinor': event.cashOutMinor,
                'cogsMinor': event.cogsMinor,
                'operatingExpenseMinor': event.operatingExpenseMinor,
                'taxCollectedMinor': event.taxCollectedMinor,
                'receivableDeltaMinor': event.receivableDeltaMinor,
                'payableDeltaMinor': event.payableDeltaMinor,
                'customerDepositDeltaMinor': event.customerDepositDeltaMinor,
                'inventoryDeltaMilliunits': event.inventoryDeltaMilliunits,
                'previousHash': event.previousHash,
                'integrityHash': event.integrityHash,
              })
          .toList(),
    });
    final synced = response.data is Map ? response.data['synced'] : null;
    if (synced is! List) return;
    final ids = synced
        .whereType<Map>()
        .map((row) => row['localId'])
        .whereType<int>()
        .toList();
    await DatabaseHelper.instance.markFinancialEventsSynced(ids);
  }

  static Future<void> resolveSaleSyncConflict({
    required Map<String, dynamic> conflict,
    required String resolution,
  }) async {
    await ensureInitialized();
    final localId = conflict['local_id'];
    final deviceId = conflict['device_id'];
    final uuid = conflict['uuid'];
    if (localId is! int || deviceId is! String || uuid is! String) return;
    final response =
        await _dio.post('$backendUrl/sales/sync/conflicts/resolve', data: {
      'device_id': deviceId,
      'local_id': localId,
      'resolution': resolution,
    });
    if (response.data is Map && response.data['resolved'] == true) {
      await DatabaseHelper.instance.resolveSaleSyncConflict(
        uuid: uuid,
        localId: localId,
        resolution: resolution,
      );
    }
  }

  /// Mirrors customer accounts and their append-only credit ledger. This is
  /// intentionally a complete, idempotent batch: customers are small and the
  /// ledger is the audit trail, so retrying is safer than maintaining another
  /// local sync flag that could miss an edited customer.
  static Future<void> syncCustomersAndCreditToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();
    final customers = await DatabaseHelper.instance.getAllCustomersForSync();
    if (customers.isEmpty) return;
    final byId = <int, String>{
      for (final customer in customers)
        if (customer.id != null) customer.id!: customer.uuid,
    };
    final entries = await DatabaseHelper.instance.getAllCreditEntriesForSync();
    const customerBatchSize = 200;
    const entryBatchSize = 500;
    for (var start = 0; start < customers.length; start += customerBatchSize) {
      final batch = customers.skip(start).take(customerBatchSize);
      await _dio.post('$backendUrl/credit/sync', data: {
        'customers': batch
            .map((customer) => <String, dynamic>{
                  'localUuid': customer.uuid,
                  'name': customer.name,
                  'phone': customer.phone,
                  'tin': customer.tin,
                  'notes': customer.notes,
                  'creditLimitMinor': customer.creditLimitMinor,
                  'balanceMinor': customer.balanceMinor,
                  'active': customer.active,
                  'createdAt': customer.createdAt,
                })
            .toList(),
        'entries': const <Map<String, dynamic>>[],
      });
    }
    for (var start = 0; start < entries.length; start += entryBatchSize) {
      final batch = entries.skip(start).take(entryBatchSize);
      await _dio.post('$backendUrl/credit/sync', data: {
        'customers': const <Map<String, dynamic>>[],
        'entries': batch
            .where((entry) => byId[entry.customerId] != null)
            .map((entry) => <String, dynamic>{
                  'localUuid': entry.uuid,
                  'customerUuid': byId[entry.customerId],
                  'entryType': entry.entryType.wire,
                  'amountMinor': entry.amountMinor,
                  'saleLocalId': entry.saleId,
                  'returnLocalId': entry.returnId,
                  'paymentMethod': entry.paymentMethod,
                  'reference': entry.reference,
                  'staffName': entry.staffName,
                  'note': entry.note,
                  'createdAt': entry.createdAt,
                })
            .toList(),
      });
    }
  }

  /// Pushes complete Fashion lay-by snapshots. The server stores the current
  /// lifecycle state idempotently under the till's local id; item and payment
  /// rows remain embedded snapshots so admin reporting never needs local
  /// integer foreign keys from another device.
  static Future<void> syncLaybysToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();
    final rows = await DatabaseHelper.instance.getUnsyncedLaybys();
    if (rows.isEmpty) return;
    final customers = await DatabaseHelper.instance.getAllCustomersForSync();
    final customerUuidById = <int, String>{
      for (final customer in customers)
        if (customer.id != null) customer.id!: customer.uuid,
    };
    final products =
        await DatabaseHelper.instance.getProducts(activeOnly: false);
    final productRemoteIdById = <int, String>{
      for (final product in products)
        if (product.id != null && product.remoteId != null)
          product.id!: product.remoteId!,
    };
    final deviceId = await _syncDeviceId();
    final payload = rows
        .map((row) => <String, dynamic>{
              'localId': row['id'],
              'deviceId': deviceId,
              'uuid': row['uuid'],
              'customerUuid': row['customer_uuid'] ??
                  customerUuidById[(row['customer_id'] as num?)?.toInt()] ??
                  'local:${row['customer_id']}',
              'status': row['status'],
              'totalMinor': row['total_minor'],
              'paidMinor': row['paid_minor'],
              'dueAt': row['due_at'],
              'createdAt': row['created_at'],
              'staffName': row['staff_name'],
              'staffId': row['staff_id'],
              'saleLocalId': row['sale_id'],
              'completedAt': row['completed_at'],
              'cancelledAt': row['cancelled_at'],
              'items': (row['items'] as List)
                  .whereType<Map>()
                  .map((item) => <String, dynamic>{
                        'productId': productRemoteIdById[
                                (item['product_id'] as num?)?.toInt()] ??
                            'local:${item['product_id']}',
                        'productName': item['product_name'],
                        'variantId': item['variant_id'],
                        'variantName': item['variant_name'],
                        'qty': item['qty'],
                        'unitPriceMinor': item['unit_price_minor'],
                        'unitCostMinor': item['unit_cost_minor'],
                        'discountMinor': item['discount_minor'],
                        'totalMinor': item['total_minor'],
                      })
                  .toList(),
              'payments': (row['payments'] as List)
                  .whereType<Map>()
                  .map((payment) => <String, dynamic>{
                        'localId': payment['id'],
                        'method': payment['method'],
                        'amountMinor': payment['amount_minor'],
                        'direction': payment['direction'] ?? 'in',
                        'reference': payment['reference'],
                        'createdAt': payment['created_at'],
                        'staffName': payment['staff_name'],
                        'staffId': payment['staff_id'],
                      })
                  .toList(),
            })
        .toList();
    final response =
        await _dio.post('$backendUrl/laybys/sync', data: {'laybys': payload});
    final synced = response.data['synced'] as List?;
    final confirmed = <int>[
      for (final item in synced ?? const [])
        if (item is Map && item['localId'] is int) item['localId'] as int,
    ];
    await DatabaseHelper.instance.markLaybysSynced(confirmed);
  }

  static Future<void> syncExchangesToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();
    final rows = await DatabaseHelper.instance.getUnsyncedExchanges();
    if (rows.isEmpty) return;
    final deviceId = await _syncDeviceId();
    final payload = rows
        .map((row) => <String, dynamic>{
              'localId': row['id'],
              'deviceId': deviceId,
              'uuid': row['uuid'],
              'originalSaleLocalId': row['original_sale_id'],
              'returnLocalId': row['return_id'],
              'replacementSaleLocalId': row['replacement_sale_id'],
              'status': row['status'],
              'returnedTotalMinor': row['returned_total_minor'],
              'replacementTotalMinor': row['replacement_total_minor'],
              'differenceMinor': row['difference_minor'],
              'differenceDirection': row['difference_direction'],
              'reason': row['reason'],
              'staffName': row['staff_name'],
              'staffId': row['staff_id'],
              'createdAt': row['created_at'],
            })
        .toList();
    final response = await _dio
        .post('$backendUrl/exchanges/sync', data: {'exchanges': payload});
    final synced = response.data['synced'] as List?;
    await DatabaseHelper.instance.markExchangesSynced([
      for (final item in synced ?? const [])
        if (item is Map && item['localId'] is int) item['localId'] as int,
    ]);
  }

  /// Pulls the tenant credit snapshot after upload. This makes balances and
  /// customer history available on another till without copying PINs or
  /// relying on device-local integer ids.
  static Future<void> pullCustomersAndCreditFromBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();
    final customers = <Map<String, dynamic>>[];
    final entries = <Map<String, dynamic>>[];
    var customerOffset = 0;
    var entryOffset = 0;
    var customersDone = false;
    var entriesDone = false;
    while (true) {
      final response = await _dio
          .get('$backendUrl/credit/sync', queryParameters: <String, dynamic>{
        'customerLimit': 200,
        'customerOffset': customerOffset,
        'includeCustomers': !customersDone,
        'entryLimit': 500,
        'entryOffset': entryOffset,
        'includeEntries': !entriesDone,
      });
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      if (!customersDone) {
        customers.addAll((data['customers'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row)));
      }
      if (!entriesDone) {
        entries.addAll((data['entries'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row)));
      }
      final nextCustomer = data['nextCustomerOffset'];
      final nextEntry = data['nextEntryOffset'];
      if (!customersDone) {
        if (nextCustomer is num) {
          customerOffset = nextCustomer.toInt();
        } else {
          customersDone = true;
        }
      }
      if (!entriesDone) {
        if (nextEntry is num) {
          entryOffset = nextEntry.toInt();
        } else {
          entriesDone = true;
        }
      }
      if (customersDone && entriesDone) break;
    }
    await DatabaseHelper.instance.mergeRemoteCreditSnapshot(
      customers: customers,
      entries: entries,
    );
  }

  /// This device's product ids, mapped to the server's UUIDs.
  ///
  /// One read per sync, not one per row: a busy day is a few hundred sales and
  /// each one would otherwise walk the catalogue. A product that has never
  /// been synced has no remote id and is simply absent from the map — the
  /// callers send null, and the server keeps the name.
  static Future<Map<int, String>> _productRemoteIds() async {
    final List<Product> products =
        await DatabaseHelper.instance.getProducts(activeOnly: false);
    return <int, String>{
      for (final Product product in products)
        if (product.id != null && product.remoteId != null)
          product.id!: product.remoteId!,
    };
  }

  /// One sale, in the shape the server reads.
  ///
  /// The MONEY IS IN MINOR UNITS — the integer cents the till counts in. The
  /// server's columns are major units and it converts once, on the way in; a
  /// float of shillings would lose a cent on the way and a ledger that is a
  /// cent out is a ledger that does not reconcile against the drawer.
  static Map<String, dynamic> _salePayload(
    Sale sale,
    Map<int, String> productRemoteIds,
    String deviceId,
    List<SalePayment> tenders,
  ) =>
      {
        'localId': sale.id,
        'deviceId': deviceId,
        'staffName': sale.staffName,
        if (sale.buyerName?.trim().isNotEmpty ?? false)
          'buyerName': sale.buyerName!.trim(),
        if (sale.buyerTin?.trim().isNotEmpty ?? false)
          'buyerTin': sale.buyerTin!.trim(),
        'paymentMethod': sale.paymentMethod,
        'paymentReference': sale.paymentReference,
        'total': sale.total.minorUnits,
        'profit': sale.profit.minorUnits,
        'amountTendered': sale.amountTendered.minorUnits,
        'changeGiven': sale.changeGiven.minorUnits,
        'createdAt': sale.createdAt,
        if (tenders.isNotEmpty)
          'tenders': tenders
              .map((SalePayment tender) => <String, dynamic>{
                    'localUuid': tender.uuid,
                    'method': tender.method,
                    'amountMinor': tender.amountMinor,
                    'tenderedMinor': tender.tenderedMinor,
                    'changeMinor': tender.changeMinor,
                    'reference': tender.reference,
                    'status': tender.status.wire,
                    'createdAt': tender.createdAt.toIso8601String(),
                  })
              .toList(),
        'items': sale.items
            .map((SaleItem item) => <String, dynamic>{
                  // Null when the product has never been synced: the server
                  // still records the line by name, and linking it is better
                  // done late than a sale refused at the door.
                  'productId': productRemoteIds[item.productId],
                  'productName': item.productName,
                  'qty': item.qty,
                  'unitPrice': item.unitPrice.minorUnits,
                  'unitCost': item.unitCost.minorUnits,
                  'vatMinor': item.vatMinor,
                  'taxableMinor': item.taxableMinor,
                  'taxClass': item.taxClass,
                  'taxRuleId': item.taxRuleId,
                  'taxRuleVersion': item.taxRuleVersion,
                  'vatRateBps': item.vatRateBps,
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

    final deviceId = await _syncDeviceId();
    while (true) {
      final shifts = await DatabaseHelper.instance.getUnsyncedShifts();
      if (shifts.isEmpty) return;
      final response = await _dio.post('$backendUrl/shifts/sync', data: {
        'shifts': shifts
            .map((Map<String, dynamic> shift) => <String, dynamic>{
                  'localId': shift['id'],
                  'deviceId': deviceId,
                  'createdAt': shift['start_time'],
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
      final confirmed = <int>[
        for (final item in synced)
          if (item is Map && item['localId'] is int) item['localId'] as int,
      ];
      await DatabaseHelper.instance.markShiftsSynced(confirmed);
      if (confirmed.isEmpty || shifts.length < 200) return;
    }
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

    final deviceId = await _syncDeviceId();

    // A cup belongs to a DRINK, and the server names drinks by UUID. See
    // `_productRemoteIds`.
    final Map<int, String> remotes = await _productRemoteIds();

    while (true) {
      final cups = await DatabaseHelper.instance.getUnsyncedShotCups();
      if (cups.isEmpty) return;
      final response = await _dio.post('$backendUrl/shot-cups/sync', data: {
        'shotCups': cups
            .map((ShotCup cup) => <String, dynamic>{
                  'localId': cup.id,
                  'deviceId': deviceId,
                  'productId': remotes[cup.productId],
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
      final confirmed = <int>[
        for (final item in synced)
          if (item is Map && item['localId'] is int) item['localId'] as int,
      ];
      await DatabaseHelper.instance.markShotCupsSynced(confirmed);
      if (confirmed.isEmpty || cups.length < 500) return;
    }
  }

  /// Pulls serving configurations created on another till. The backend keeps
  /// these as operational records, so the remote product UUID is resolved to
  /// this phone's local product id before the row is merged.
  static Future<void> pullShotCupsFromBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();
    final products =
        await DatabaseHelper.instance.getProducts(activeOnly: false);
    final byRemoteId = <String, int>{
      for (final product in products)
        if (product.id != null && product.remoteId != null)
          product.remoteId!: product.id!,
    };
    final prefs = await _prefsInstance;
    final workspaceKey = await WorkspaceService.activeWorkspaceKey();
    final cursorScope =
        workspaceKey.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final cursorKey = 'remote_operational_cursor_${cursorScope}_shot-cups';
    var cursor = prefs.getString(cursorKey);

    // A serving catalogue is small in most shops, but it is still an
    // operational stream and must not lose rows after a long offline period.
    // Keep the same bounded page drain and non-advancing-cursor guard used by
    // the other operational streams.
    for (var page = 0; page < 100; page++) {
      final response = await _dio.get(
        '$backendUrl/shot-cups/sync',
        queryParameters:
            cursor == null ? null : <String, dynamic>{'since': cursor},
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      final rows = data['shotCups'];
      if (rows is! List) break;
      for (final raw in rows.whereType<Map>()) {
        final remoteProductId = raw['productId'];
        final localProductId = byRemoteId[remoteProductId];
        if (remoteProductId is! String || localProductId == null) continue;
        await DatabaseHelper.instance.mergeRemoteShotCup(
          productId: localProductId,
          productName: raw['productName'] as String? ?? '',
          capacityMl: (raw['capacityMl'] as num?)?.toInt() ?? 0,
          priceMinor: (raw['price'] as num?)?.toInt() ?? 0,
          label: raw['label'] as String? ?? 'Small cup',
          active: raw['active'] != false,
        );
      }
      final responseCursor = data['nextCursor'];
      final nextCursor = responseCursor is String && responseCursor.isNotEmpty
          ? responseCursor
          : cursor;
      if (nextCursor == null || nextCursor.isEmpty || nextCursor == cursor) {
        break;
      }
      await prefs.setString(cursorKey, nextCursor);
      cursor = nextCursor;
      if (rows.length < 500) break;
    }
  }

  /// Pulls the operational rows created by other tills into a tenant-scoped
  /// local mirror. They are not inserted into the local financial tables:
  /// integer shift/category/product ids are device-local and guessing a join
  /// would corrupt offline books. The original payload is preserved and can be
  /// used by the owner/sync centre, while the local ledger remains append-only.
  static Future<void> pullOperationalRecordsFromBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();
    final prefs = await _prefsInstance;
    final workspaceKey = await WorkspaceService.activeWorkspaceKey();
    final cursorScope =
        workspaceKey.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    const sources = <({String path, String key, String kind})>[
      (path: 'shifts', key: 'shifts', kind: 'shifts'),
      (path: 'returns', key: 'returns', kind: 'returns'),
      (path: 'purchases', key: 'purchases', kind: 'purchases'),
      (path: 'expenses', key: 'expenses', kind: 'expenses'),
      (path: 'till-movements', key: 'tillMovements', kind: 'till-movements'),
      (path: 'stock-movements', key: 'stockMovements', kind: 'stock-movements'),
      (path: 'drawer-events', key: 'drawerEvents', kind: 'drawer-events'),
      (path: 'reorder', key: 'reorder', kind: 'reorder'),
    ];
    for (final source in sources) {
      try {
        final cursorKey =
            'remote_operational_cursor_${cursorScope}_${source.kind}';
        String? cursor = prefs.getString(cursorKey);
        // The backend returns 500 rows at a time. Drain a bounded number of
        // advancing pages now so a till that was offline for months does not
        // wait for a separate six-hour cycle per page. The bound protects a
        // damaged cursor or an unexpectedly large tenant from monopolising
        // the sync session.
        for (var page = 0; page < 100; page++) {
          final response = await _dio.get(
            '$backendUrl/${source.path}/sync',
            queryParameters:
                cursor == null ? null : <String, dynamic>{'since': cursor},
          );
          final rawRows =
              response.data is Map ? response.data[source.key] : null;
          if (rawRows is! List) break;
          String? newest;
          for (final raw in rawRows.whereType<Map>()) {
            final row = Map<String, dynamic>.from(raw);
            final remoteId = row.remove('remoteId');
            final createdAt = row.remove('remoteCreatedAt');
            final updatedAt = row.remove('remoteUpdatedAt');
            if (remoteId is! String || remoteId.isEmpty) continue;
            if (source.kind == 'reorder') {
              await DatabaseHelper.instance
                  .mergeRemoteReorderRecord(<String, dynamic>{
                ...row,
                'remoteId': remoteId,
              });
            }
            await DatabaseHelper.instance.mergeRemoteOperationalRecord(
              remoteId: remoteId,
              kind: source.kind,
              payload: row,
              deviceId: row['deviceId'] as String?,
              localId: (row['localId'] as num?)?.toInt(),
              createdAt: createdAt as String?,
              updatedAt: updatedAt as String?,
            );
            if (updatedAt is String &&
                (newest == null || updatedAt.compareTo(newest) > 0)) {
              newest = updatedAt;
            }
          }

          final responseCursor =
              response.data is Map ? response.data['nextCursor'] : null;
          final nextCursor =
              responseCursor is String && responseCursor.isNotEmpty
                  ? responseCursor
                  : newest;
          if (nextCursor == null || nextCursor.isEmpty) break;
          // Compatibility with older servers that return rows but no cursor.
          // A cursor that does not advance is a hard stop, otherwise a broken
          // server could make this loop replay the same page forever.
          if (nextCursor == cursor) break;
          await prefs.setString(cursorKey, nextCursor);
          cursor = nextCursor;
          if (rawRows.length < 500) break;
        }
      } on DioException catch (error) {
        // One operational stream being unavailable must not block catalogue,
        // sales, or the remaining streams on the next cycle.
        debugPrint('Operational pull failed for ${source.kind}: $error');
      }
    }
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

    final deviceId = await _syncDeviceId();
    final productRemoteIds = await _productRemoteIds();

    // ONE AT A TIME.
    //
    // The server takes a return on its own, and a shop's returns are rare —
    // a handful in a week, on a bad day. One request each keeps the contract
    // simple, and it means one refused return does not hold up the rest: each
    // is sent on its own, and only the ones the server confirmed are marked.
    while (true) {
      final returns = await DatabaseHelper.instance.getUnsyncedReturns();
      if (returns.isEmpty) return;
      final confirmed = <int>[];
      for (final SaleReturn entry in returns) {
        try {
          final response = await _dio.post('$backendUrl/returns', data: {
            'localId': entry.id,
            'deviceId': deviceId,
            'originalSaleLocalId': entry.saleId,
            'kind': entry.kind,
            'reason': entry.reason,
            'total': entry.total.minorUnits,
            'vatTotal': entry.vatTotal,
            'profit': entry.profit.minorUnits,
            'refundMethod': entry.refundMethod,
            'paymentReference': entry.paymentReference,
            'staffName': entry.staffName,
            'createdAt': entry.createdAt,
            'refundAllocations': entry.refundAllocations
                .map((allocation) => <String, dynamic>{
                      'salePaymentId': allocation.salePaymentId,
                      'method': allocation.method,
                      'amount': allocation.amount.minorUnits,
                      'reference': allocation.reference,
                    })
                .toList(),
            'items': entry.items
                .map((SaleReturnItem item) => <String, dynamic>{
                      // Product row ids belong to this phone. The server and
                      // other tills identify the same product by its UUID.
                      'productId': productRemoteIds[item.productId],
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
      if (confirmed.isEmpty || returns.length < 200) return;
    }
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

    final deviceId = await _syncDeviceId();
    final productRemoteIds = await _productRemoteIds();

    while (true) {
      final receipts = await DatabaseHelper.instance.getUnsyncedReceipts();
      if (receipts.isEmpty) return;
      final confirmed = <int>[];
      for (final StockReceipt receipt in receipts) {
        try {
          final response = await _dio.post('$backendUrl/purchases', data: {
            'localId': receipt.id,
            'deviceId': deviceId,
            'supplierName': receipt.supplierRef ?? '',
            'invoiceNumber': receipt.supplierRef,
            'supplierPin': receipt.supplierPin,
            'etimsInvoiceRef': receipt.etimsInvoiceRef,
            'inputVatMinor': receipt.inputVat?.minorUnits,
            'taxEvidenceStatus': receipt.taxEvidenceStatus,
            'total': receipt.totalCost.minorUnits,
            'staffName': receipt.staffName,
            'createdAt': receipt.receivedAt,
            'items': receipt.items
                .map((StockReceiptItem item) => <String, dynamic>{
                      // A receipt may be replayed by another till, so never
                      // send the originating device's integer row id.
                      'productId': productRemoteIds[item.productId],
                      'productName': item.productName,
                      'qty': item.qty,
                      'unitCost': item.unitCost.minorUnits,
                      'variantId': item.variantId,
                      'expiryDate': item.expiryDate?.toIso8601String(),
                      'batchCode': item.batchCode,
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
      if (confirmed.isEmpty || receipts.length < 100) return;
    }
  }

  /// Pushes supplier terms, product links and purchase-order drafts. This is
  /// deliberately a separate operational stream: syncing a draft never
  /// places an order or enables automatic purchasing.
  static Future<void> syncReorderingToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();
    final deviceId = await _syncDeviceId();
    final productRemoteIds = await _productRemoteIds();
    while (true) {
      final records = await DatabaseHelper.instance.getUnsyncedReorderRecords();
      if (records.isEmpty) return;
      final confirmed = <Map<String, dynamic>>[];
      for (final record in records) {
        try {
          final payload = Map<String, dynamic>.from(record['payload'] as Map);
          payload['supplier_name'] ??= payload['name'];
          if (record['kind'] == 'product_supplier') {
            payload['product_remote_id'] =
                productRemoteIds[(payload['product_id'] as num?)?.toInt()];
          }
          if (record['kind'] == 'purchase_order' && payload['lines'] is List) {
            payload['supplier_name'] ??= payload['supplier_id']?.toString();
            payload['lines'] = (payload['lines'] as List)
                .whereType<Map>()
                .map((line) => <String, dynamic>{
                      ...Map<String, dynamic>.from(line),
                      'product_remote_id': productRemoteIds[
                          (line['product_id'] as num?)?.toInt()],
                    })
                .toList();
          }
          final response = await _dio.post('$backendUrl/reorder', data: {
            'localId': record['localId'],
            'deviceId': deviceId,
            'createdAt': record['createdAt'],
            'entityKind': record['kind'],
            'payload': payload,
          });
          if (response.data is Map && response.data['localId'] is int) {
            confirmed.add(record);
          }
        } on DioException catch (error) {
          debugPrint('Reorder sync failed for ${record['kind']}: $error');
        }
      }
      await DatabaseHelper.instance.markReorderRecordsSynced(confirmed);
      if (confirmed.isEmpty || records.length < 100) return;
    }
  }

  /// Pushes the append-only stock ledger. Product snapshots are still useful
  /// for catalogue pulls, but they are not a safe multi-device inventory
  /// source: two offline tills can each upload a different cached balance.
  /// Movement rows preserve both changes so the server can reconcile them.
  static Future<void> syncStockMovementsToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();
    final deviceId = await _syncDeviceId();
    final remotes = await _productRemoteIds();
    while (true) {
      final movements =
          await DatabaseHelper.instance.getUnsyncedStockMovements();
      if (movements.isEmpty) return;
      // A movement without a remote product id cannot affect the server's
      // inventory. Keep it queued until catalogue sync creates the product.
      final uploadable = movements
          .where((movement) => remotes[movement.productId] != null)
          .toList();
      if (uploadable.isEmpty) return;

      final response =
          await _dio.post('$backendUrl/stock-movements/sync', data: {
        'stockMovements': uploadable
            .map((movement) => <String, dynamic>{
                  'localId': movement.id,
                  'deviceId': deviceId,
                  'uuid': movement.uuid,
                  'productId': remotes[movement.productId],
                  'variantId': movement.variantId,
                  'movementType': movement.type.wire,
                  'qtyDelta': movement.qtyDelta,
                  'unitCostMinor': movement.unitCostMinor,
                  'referenceType': movement.referenceType,
                  'referenceId': movement.referenceId,
                  'batchId': movement.batchId,
                  'staffId': movement.staffId,
                  'staffName': movement.staffName,
                  'note': movement.note,
                  'balanceAfter': movement.balanceAfter,
                  'createdAt': movement.createdAt.toIso8601String(),
                })
            .toList(),
      });
      final synced = response.data['synced'] as List?;
      if (synced == null) return;
      final confirmed = [
        for (final item in synced)
          if (item is Map && item['localId'] is int) item['localId'] as int,
      ];
      await DatabaseHelper.instance.markStockMovementsSynced(confirmed);
      if (confirmed.isEmpty || movements.length < 500) return;
    }
  }

  /// Mirrors offline cash-control rows for online reports and the owner's
  /// other devices. The backend stores the original payload under an
  /// idempotent tenant/kind/local-id key, so retries cannot duplicate a payout
  /// or cash drop.
  static Future<void> syncExpensesAndTillMovementsToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();

    final db = DatabaseHelper.instance;
    final deviceId = await _syncDeviceId();
    while (true) {
      final expenses = await db.getUnsyncedExpenses();
      if (expenses.isEmpty) break;
      final response = await _dio.post('$backendUrl/expenses/sync', data: {
        'expenses': expenses
            .map((row) => <String, dynamic>{
                  'localId': row['id'],
                  'deviceId': deviceId,
                  'uuid': row['uuid'],
                  'shiftId': row['shift_id'],
                  'categoryId': row['category_id'],
                  'amountMinor': row['amount_minor'],
                  'paidFrom': row['paid_from'],
                  'note': row['note'],
                  'staffId': row['staff_id'],
                  'staffName': row['staff_name'],
                  'status': row['status'],
                  'createdAt': row['created_at'],
                })
            .toList(),
      });
      final synced = response.data['synced'] as List?;
      final confirmed = [
        for (final item in synced ?? const [])
          if (item is Map && item['localId'] is int) item['localId'] as int,
      ];
      await db.markExpensesSynced(confirmed);
      if (confirmed.isEmpty || expenses.length < 200) break;
    }

    while (true) {
      final movements = await db.getUnsyncedTillMovements();
      if (movements.isEmpty) return;
      final response =
          await _dio.post('$backendUrl/till-movements/sync', data: {
        'tillMovements': movements
            .map((row) => <String, dynamic>{
                  'localId': row['id'],
                  'deviceId': deviceId,
                  'uuid': row['uuid'],
                  'shiftId': row['shift_id'],
                  'movementType': row['movement_type'],
                  'amountMinor': row['amount_minor'],
                  'note': row['note'],
                  'staffId': row['staff_id'],
                  'staffName': row['staff_name'],
                  'status': row['status'],
                  'createdAt': row['created_at'],
                })
            .toList(),
      });
      final synced = response.data['synced'] as List?;
      final confirmed = [
        for (final item in synced ?? const [])
          if (item is Map && item['localId'] is int) item['localId'] as int,
      ];
      await db.markTillMovementsSynced(confirmed);
      if (confirmed.isEmpty || movements.length < 200) return;
    }
  }

  static Future<void> syncDrawerEventsToBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();
    final deviceId = await _syncDeviceId();
    while (true) {
      final events = await DatabaseHelper.instance.getUnsyncedDrawerEvents();
      if (events.isEmpty) return;
      final response = await _dio.post('$backendUrl/drawer-events', data: {
        'drawerEvents': events
            .map((row) => <String, dynamic>{
                  'localId': row['id'],
                  'deviceId': deviceId,
                  'uuid': row['uuid'],
                  'shiftId': row['shift_id'],
                  'eventType': row['event_type'],
                  'reason': row['reason'],
                  'staffId': row['staff_id'],
                  'staffName': row['staff_name'],
                  'createdAt': row['created_at'],
                  'status': row['status'],
                })
            .toList(),
      });
      final synced = response.data['synced'] as List?;
      final confirmed = [
        for (final item in synced ?? const [])
          if (item is Map && item['localId'] is int) item['localId'] as int,
      ];
      await DatabaseHelper.instance.markDrawerEventsSynced(confirmed);
      if (confirmed.isEmpty || events.length < 500) return;
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
                'username': s.username,
                'role': s.role,
                'active': s.active,
                'pinHash': s.pinHash.startsWith('pbkdf2\$') ? s.pinHash : null,
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

  /// Pulls staff names, roles and deactivations from another device. The
  /// merge only touches profiles already provisioned locally; PINs remain
  /// device-local and are never downloaded.
  static Future<void> pullStaffFromBackend() async {
    await ensureInitialized();
    if (await tenantId == null) return;
    await _assertRowsInScope();
    final response = await _dio.get('$backendUrl/tenant/staff');
    final rows = response.data is Map ? response.data['staff'] : null;
    for (final raw
        in (rows is List ? rows : const <dynamic>[]).whereType<Map>()) {
      final remoteId = raw['id'];
      if (remoteId is! String || remoteId.isEmpty) continue;
      await DatabaseHelper.instance.mergeRemoteStaff(
        remoteId: remoteId,
        name: raw['name'] as String? ?? 'Staff',
        username: raw['username'] as String?,
        role: raw['role'] as String? ?? 'cashier',
        active: raw['active'] == true,
      );
    }
  }

  /// Uploads an opaque, device-bound encrypted copy of the complete workspace.
  /// The server stores ciphertext only; a passphrase portable export remains
  /// the path for restoring onto a different phone.
  static Future<void> syncFullBackupToBackend() async {
    await ensureInitialized();
    if (await tenantId == null || !await isIdentityVerified) return;
    final snapshot = await DatabaseHelper.instance.exportFullSnapshot();
    final workspaceKey = snapshot['workspaceKey'];
    if (workspaceKey is! String || workspaceKey.isEmpty) return;
    final clearBytes = utf8.encode(jsonEncode(snapshot));
    final payload = await EncryptedBackupService.encryptBytes(
      clearBytes,
    );
    try {
      await _dio.post('$backendUrl/backups/full', data: {
        'workspaceKey': workspaceKey,
        'kind': 'device_bound',
        'payload': payload,
        'snapshotHash': sha256.convert(clearBytes).toString(),
      });
      await DatabaseHelper.instance.recordBackupLog(
        uuid: generateUuid(),
        kind: 'cloud_full_device_bound',
        clearBytes: clearBytes.length,
        manifestJson: jsonEncode(snapshot['manifest']),
        status: 'uploaded',
      );
    } catch (_) {
      // The local encrypted snapshot remains the offline source of truth. A
      // failed attempt is still visible to the owner and is retried by the
      // next verified automatic cycle; never turn a network failure into a
      // checkout failure or discard the snapshot.
      try {
        await DatabaseHelper.instance.recordBackupLog(
          uuid: generateUuid(),
          kind: 'cloud_full_device_bound',
          clearBytes: clearBytes.length,
          manifestJson: jsonEncode(snapshot['manifest']),
          status: 'upload_failed',
        );
      } catch (_) {
        // Observability must not replace the original network error.
      }
      rethrow;
    }
  }

  /// Uploads a passphrase-protected full snapshot that can be restored on a
  /// different phone. Automatic sync deliberately remains device-bound so it
  /// never stores a reusable backup secret without an owner choosing one.
  static Future<void> syncPortableFullBackupToBackend(String passphrase) async {
    await ensureInitialized();
    if (await tenantId == null || !await isIdentityVerified) return;
    final snapshot = await DatabaseHelper.instance.exportFullSnapshot();
    final workspaceKey = snapshot['workspaceKey'];
    if (workspaceKey is! String || workspaceKey.isEmpty) return;
    final clearBytes = utf8.encode(jsonEncode(snapshot));
    final payload = await EncryptedBackupService.buildPortablePayload(
      clearBytes: clearBytes,
      passphrase: passphrase,
    );
    try {
      await _dio.post('$backendUrl/backups/full', data: {
        'workspaceKey': workspaceKey,
        'kind': 'portable',
        'payload': payload,
        'snapshotHash': sha256.convert(clearBytes).toString(),
      });
      await DatabaseHelper.instance.recordBackupLog(
        uuid: generateUuid(),
        kind: 'cloud_full_portable',
        clearBytes: clearBytes.length,
        manifestJson: jsonEncode(snapshot['manifest']),
        status: 'uploaded',
      );
    } catch (_) {
      try {
        await DatabaseHelper.instance.recordBackupLog(
          uuid: generateUuid(),
          kind: 'cloud_full_portable',
          clearBytes: clearBytes.length,
          manifestJson: jsonEncode(snapshot['manifest']),
          status: 'upload_failed',
        );
      } catch (_) {
        // Preserve the upload error if the local log is unavailable too.
      }
      rethrow;
    }
  }

  /// Restores the latest ciphertext snapshot for this workspace on this same
  /// device. A portable passphrase backup is still required for a new phone.
  static Future<bool> restoreFullBackupFromBackend() async {
    await ensureInitialized();
    if (await tenantId == null || !await isIdentityVerified) return false;
    final workspaceKey = await WorkspaceService.activeWorkspaceKey();
    final response = await _dio.get('$backendUrl/backups/full',
        queryParameters: {
          'workspaceKey': workspaceKey,
          'kind': 'device_bound'
        });
    final data = response.data;
    if (data is! Map || data['payload'] is! String) return false;
    final clear = await EncryptedBackupService.decryptBytes(
        utf8.encode(data['payload'] as String));
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map) throw const FormatException('Invalid cloud backup');
    await DatabaseHelper.instance
        .restoreFullSnapshot(Map<String, Object?>.from(decoded));
    return true;
  }

  /// Restores an owner-created portable cloud copy on any device. The
  /// passphrase is never sent to the backend.
  static Future<bool> restorePortableFullBackupFromBackend(
      String passphrase) async {
    await ensureInitialized();
    if (await tenantId == null || !await isIdentityVerified) return false;
    final workspaceKey = await WorkspaceService.activeWorkspaceKey();
    final response = await _dio.get('$backendUrl/backups/full',
        queryParameters: {'workspaceKey': workspaceKey, 'kind': 'portable'});
    final data = response.data;
    if (data is! Map || data['payload'] is! String) return false;
    final clear = await EncryptedBackupService.decryptPortableBytes(
      encodedBytes: utf8.encode(data['payload'] as String),
      passphrase: passphrase,
    );
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map) throw const FormatException('Invalid cloud backup');
    await DatabaseHelper.instance.restoreFullSnapshot(
      Map<String, Object?>.from(decoded),
      allowWorkspaceMismatch: true,
    );
    return true;
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

  static Future<List<IncomingPayment>> fetchIncomingMpesa({
    String? since,
    String status = 'unclaimed',
  }) async {
    await ensureInitialized();
    final response = await _dio.get<Map<String, dynamic>>(
      '$backendUrl/mpesa/incoming',
      queryParameters: <String, dynamic>{
        'status': status,
        if (since != null && since.isNotEmpty) 'since': since,
      },
    );
    final rows = response.data?['payments'] as List? ?? const [];
    return rows.whereType<Map>().map((raw) {
      final row = Map<String, dynamic>.from(raw);
      return IncomingPayment(
        remoteId: row['remoteId'] as String,
        transactionId: row['transId'] as String,
        amount: Money.fromMajor(num.parse(row['amount'].toString())),
        payerMasked: row['payerLabel'] as String? ?? '',
        receivedAt: DateTime.tryParse(row['receivedAt'].toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        status: row['status'] as String? ?? status,
        claimedAt: DateTime.tryParse(row['claimedAt']?.toString() ?? ''),
        claimedBy: row['claimedByDevice'] as String?,
      );
    }).toList();
  }

  /// Caches incoming till payments for offline matching and for the manager's
  /// reconciliation screen. Pull all three states so a claim made on another
  /// till is reflected locally instead of leaving a stale unclaimed badge.
  static Future<void> pullIncomingMpesaToLocal() async {
    await ensureInitialized();
    if (await tenantId == null || !await isIdentityVerified) return;
    final db = DatabaseHelper.instance;
    for (final status in const ['unclaimed', 'claimed', 'ignored']) {
      final payments = await fetchIncomingMpesa(status: status);
      for (final payment in payments) {
        await db.upsertIncomingPayment(payment);
      }
    }
  }

  static Future<void> claimIncomingMpesa({
    required String remoteId,
    required String saleUuid,
  }) async {
    await ensureInitialized();
    await _dio.post('$backendUrl/mpesa/incoming/$remoteId/claim', data: {
      'sale_uuid': saleUuid,
      'device': await _syncDeviceId(),
    });
  }

  /// Retries claims that were committed locally while the till was offline.
  /// A 409 is permanent ownership information, not a transport failure, so it
  /// becomes a visible local dispute instead of retrying forever.
  static Future<void> syncIncomingMpesaClaims() async {
    await ensureInitialized();
    if (!await isIdentityVerified) return;
    final db = DatabaseHelper.instance;
    final claims = await db.getPendingIncomingPaymentClaims();
    for (final claim in claims) {
      final remoteId = claim['remote_id'] as String? ?? '';
      if (remoteId.isEmpty) continue;
      try {
        await claimIncomingMpesa(
          remoteId: remoteId,
          saleUuid: claim['sale_uuid'] as String? ?? '',
        );
        await db.resolveIncomingPaymentClaim(remoteId);
        final cached = await db.getIncomingPayments(status: 'unclaimed');
        final payment = cached.where((item) => item.remoteId == remoteId);
        if (payment.isNotEmpty) {
          final item = payment.first;
          await db.upsertIncomingPayment(IncomingPayment(
            remoteId: item.remoteId,
            transactionId: item.transactionId,
            amount: item.amount,
            payerMasked: item.payerMasked,
            receivedAt: item.receivedAt,
            status: 'claimed',
            claimedAt: DateTime.now(),
            claimedBy: await _syncDeviceId(),
          ));
        }
      } on DioException catch (error) {
        if (error.response?.statusCode == 409) {
          await db.markIncomingPaymentClaimDisputed(
            remoteId,
            'This payment was claimed by another till.',
          );
        }
      }
    }
  }

  static Future<void> ignoreIncomingMpesa({
    required String remoteId,
    required String reason,
  }) async {
    await ensureInitialized();
    await _dio.post('$backendUrl/mpesa/incoming/$remoteId/ignore', data: {
      'reason': reason,
    });
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
