import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../services/staff_credential_cache.dart';
import '../widgets/staff_pin_change_dialog.dart';
import '../services/workspace_service.dart';
import '../theme/app_colors.dart';
import '../utils/pin_rules.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../ui/onboarding_style.dart';

/// The username + password entry point for staff.
///
/// Redesigned to match the product palette: forest primary, electric accent,
/// media window header, and styled actions.
class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key, this.staffLoader});

  final Future<List<Staff>> Function()? staffLoader;

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _shopIdController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;
  Map<String, dynamic>? _lastAuthDiagnostics;
  String? _lastAuthSummary;
  List<LocalShop> _shops = const <LocalShop>[];
  bool _shopChosen = false;
  bool _askingShop = false;
  bool _shopsLoaded = false;
  String? _activeShopName;

  // The shop ID is always needed for a remote staff login on a device that
  // does not already hold the shop. Show the field whenever there is no active
  // tenant, and also allow entering it manually even when local shops exist.
  bool get _needsShopId =>
      _shopsLoaded && (_shops.isEmpty || _activeShopName == null);

  @override
  void initState() {
    super.initState();
    final AppState appState = context.read<AppState>();
    if (appState.rememberedStaffUsername != null) {
      _usernameController.text = appState.rememberedStaffUsername!;
    }
    _loadShops();
  }

  Future<void> _loadShops() async {
    final shops = await WorkspaceServiceShops.localShops();
    final activeKey = await WorkspaceService.activeWorkspaceKey();
    if (!mounted) return;
    setState(() {
      _shops = shops;
      _shopsLoaded = true;
      _shopChosen = shops.length <= 1;
      final matches = shops.where((shop) => shop.workspaceKey == activeKey);
      _activeShopName = matches.isEmpty ? null : matches.first.shopName;
    });
  }

  Future<LocalShop?> _chooseShop() {
    return showDialog<LocalShop>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context).staffLoginChooseShop),
        content: SizedBox(
          width: double.maxFinite,
          height: (_shops.length * 64).clamp(64, 320).toDouble(),
          child: ListView.builder(
            itemCount: _shops.length,
            itemBuilder: (_, index) {
              final shop = _shops[index];
              return ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(shop.shopName),
                subtitle: Text(
                    shop.isBackendLinked ? 'Connected shop' : 'Offline shop'),
                onTap: () => Navigator.of(dialogContext).pop(shop),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppLocalizations.of(context).staffLoginCancel),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureShopSelected() async {
    if (_shopChosen || _shops.length <= 1) return true;
    if (_askingShop) return false;
    _askingShop = true;
    try {
      final shop = await _chooseShop();
      if (shop == null || !mounted) return false;
      await context.read<AppState>().switchWorkspace(
            shop.workspaceKey,
            signIn: false,
          );
      if (!mounted) return false;
      setState(() {
        _shopChosen = true;
        _activeShopName = shop.shopName;
        _error = null;
      });
      return true;
    } finally {
      _askingShop = false;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _shopIdController.dispose();
    super.dispose();
  }

  Future<Staff?> _mergeOnlineStaff(
    Map<String, dynamic>? response,
    Staff? fallback, {
    required String username,
    required String pin,
    String? requestedTenant,
  }) async {
    if (response == null) return fallback;
    if (response['_rejected'] == true) return null;
    final nested = response['staff'];
    final Map<String, dynamic> staffMap =
        nested is Map ? Map<String, dynamic>.from(nested) : response;
    if (staffMap['active'] == false) return null;
    var selectedTenant = await BackendService.tenantId;
    final responseTenant = staffMap['tenant_id'] as String?;
    if (responseTenant == null || responseTenant.isEmpty) return null;
    if (requestedTenant != null &&
        requestedTenant.isNotEmpty &&
        responseTenant != requestedTenant) {
      return null;
    }
    if (selectedTenant == null) {
      final workspaceKey =
          'tenant_${responseTenant.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';
      await WorkspaceService.register(
        workspaceKey: workspaceKey,
        tenantId: responseTenant,
        shopName: staffMap['shop_name'] as String? ?? 'Shop',
      );
      await WorkspaceService.setActiveWorkspace(workspaceKey);
      selectedTenant = await BackendService.tenantId;
    }
    if (selectedTenant != responseTenant) {
      return null;
    }
    final rawRemoteId = staffMap['remoteId'] ?? staffMap['staff_id'];
    final remoteId = rawRemoteId is String ? rawRemoteId : null;
    if (remoteId == null || remoteId.isEmpty) return null;
    final String fallbackHash = fallback?.pinHash ?? '';
    final bool keepFallbackHash = fallbackHash.startsWith('pbkdf2\$') &&
        !AuthService.needsUpgrade(fallbackHash);
    final String pinHash =
        keepFallbackHash ? fallbackHash : await AuthService.hashPin(pin);
    return DatabaseHelper.instance.mergeAuthenticatedStaff(
      remoteId: remoteId,
      username: username,
      name: staffMap['name'] as String? ?? fallback?.name ?? username,
      role: staffMap['role'] as String? ?? fallback?.role ?? 'cashier',
      pinHash: pinHash,
    );
  }

  Future<void> _requestForgottenPin() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => _error = 'Enter your staff username first.');
      return;
    }
    final tenantId = await BackendService.tenantId ??
        (_needsShopId ? _shopIdController.text.trim() : null);
    if (tenantId == null || tenantId.isEmpty) {
      setState(() => _error = 'Select the shop before requesting a PIN reset.');
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forgot your staff PIN?'),
        content: const Text(
            'Send a private reset request to the shop owner. The owner will give you a temporary PIN, which you should change immediately.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Notify owner')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await BackendService.requestStaffPinReset(
          username: username, tenantId: tenantId);
      if (!mounted) return;
      setState(
          () => _error = 'Request sent. Ask the owner for your temporary PIN.');
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not send the request: $e';
        _lastAuthSummary = 'PIN reset request failed';
        _lastAuthDiagnostics = <String, dynamic>{
          'phase': 'request_staff_pin_reset',
          'tenantId': tenantId,
          'username': username,
          'backendUrl': BackendService.backendUrl,
          'exceptionType': e.runtimeType.toString(),
          'exception': e.toString(),
          'stackTrace': st.toString(),
        };
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _loading) return;
    if (!kIsWeb && !await _ensureShopSelected()) return;
    setState(() {
      _loading = true;
      _error = null;
      _lastAuthDiagnostics = null;
      _lastAuthSummary = null;
    });
    try {
      final String username = _usernameController.text.trim();
      final String password = _passwordController.text.trim();
      final String shopIdField = _shopIdController.text.trim().toLowerCase();
      String? activeTenant;
      if (!kIsWeb) {
        try {
          activeTenant = await BackendService.tenantId;
        } catch (e) {
          activeTenant = null;
          if (kDebugMode) {
            debugPrint('[StaffLogin] Failed to read active tenant: $e');
          }
        }
      }
      final String? requestedTenant =
          activeTenant ?? (shopIdField.isNotEmpty ? shopIdField : null);
      final Map<String, dynamic> baseDiagnostics = <String, dynamic>{
        'phase': 'submit_start',
        'mode': kIsWeb ? 'web_diagnostic' : 'native',
        'backendUrl': BackendService.backendUrl,
        'endpoint': '${BackendService.backendUrl}/tenant/staff/authenticate',
        'activeTenant': activeTenant,
        'requestedTenant': requestedTenant,
        'shopIdField': shopIdField,
        'username': username,
        'pinLength': password.length,
        'timestamp': DateTime.now().toIso8601String(),
      };
      if (!mounted) return;
      setState(() {
        _lastAuthDiagnostics = baseDiagnostics;
        _lastAuthSummary = 'Preparing staff authentication request';
      });
      if (kDebugMode) {
        debugPrint(
          '[StaffLogin] submit mode=${baseDiagnostics['mode']} '
          'tenant=$requestedTenant user=$username pinLen=${password.length}',
        );
      }

      if (kIsWeb) {
        if (requestedTenant == null || requestedTenant.isEmpty) {
          setState(() {
            _error = 'Enter the Shop ID to test staff login against the backend.';
            _lastAuthSummary = 'Missing Shop ID / tenant';
            _lastAuthDiagnostics = <String, dynamic>{
              'backendUrl': BackendService.backendUrl,
              'endpoint': '${BackendService.backendUrl}/tenant/staff/authenticate',
              'tenantId': requestedTenant,
              'username': username,
              'note':
                  'Web diagnostic mode calls the remote staff auth endpoint only; local device DB/session flows are unavailable in browser.',
            };
          });
          return;
        }
        final Map<String, dynamic>? backendResponse =
            await BackendService.authenticateStaff(
          username: username,
          pin: password,
          tenantId: requestedTenant,
        );
        final Map<String, dynamic>? diagnostics =
            BackendService.staffAuthenticationDiagnostics(backendResponse);
        final bool rejected =
            BackendService.isAuthoritativeStaffAuthenticationRejection(
          backendResponse,
        );
        final bool transportFailure = backendResponse?['_transportFailure'] == true;
        final bool success = !rejected &&
            !transportFailure &&
            backendResponse != null &&
            backendResponse.isNotEmpty;
        if (!mounted) return;
        setState(() {
          _lastAuthDiagnostics = diagnostics ?? _lastAuthDiagnostics;
          _lastAuthSummary = success
              ? 'Remote authentication succeeded'
              : rejected
                  ? 'Remote authentication rejected by backend'
                  : transportFailure
                      ? 'Remote authentication request failed (transport/server)'
                      : 'Remote authentication returned no usable staff payload';
          _error = success
              ? 'Web diagnostic mode: remote staff authentication succeeded. Local sign-in/session persistence is not performed in browser.'
              : _formatStaffAuthError(
                  backendResponse: backendResponse,
                  fallback: AppLocalizations.of(context).loginWrongCredentials,
                  detailed: true,
                );
        });
        return;
      }

      final String userKey = username;
      if (await AuthService.isTillLockedOut()) {
        final Duration? remaining = await AuthService.tillLockoutRemaining();
        if (!mounted) return;
        setState(
            () => _error = 'Too many wrong PINs on this till. Try again in '
                '${remaining?.inSeconds ?? 0}s.');
        return;
      }
      if (await AuthService.isLockedOut(userKey)) {
        final Duration? remaining = await AuthService.lockoutRemaining(userKey);
        if (!mounted) return;
        setState(() => _error =
            'Too many wrong PINs. Try again in ${remaining?.inSeconds ?? 0}s.');
        return;
      }

      final List<Staff> localStaff = await (widget.staffLoader?.call() ??
          DatabaseHelper.instance.getStaff());
      Map<String, dynamic>? onlineResponse;
      Staff? staff = localStaff.cast<Staff?>().firstWhere(
            (Staff? s) => s?.username?.toLowerCase() == username.toLowerCase(),
            orElse: () => null,
          );
      final bool localPinVerified =
          staff != null && await AuthService.verifyPin(password, staff.pinHash);
      if (requestedTenant == null && (staff == null || !localPinVerified)) {
        setState(() => _error = 'Enter the shop ID supplied by the owner.');
        return;
      }

      if (staff != null && localPinVerified) {
        await AuthService.recordSuccess(userKey);
        if (AuthService.needsUpgrade(staff.pinHash) && staff.id != null) {
          final upgradedHash = await AuthService.hashPin(password);
          await DatabaseHelper.instance.updateStaffPin(staff.id!, upgradedHash);
          staff = Staff(
            id: staff.id,
            name: staff.name,
            username: staff.username,
            pinHash: upgradedHash,
            active: staff.active,
            remoteId: staff.remoteId,
            role: staff.role,
          );
        }
        if (requestedTenant != null) {
          try {
            if (!mounted) return;
            setState(() {
              _lastAuthSummary =
                  'Local PIN verified; checking remote staff authentication';
              _lastAuthDiagnostics = <String, dynamic>{
                ...?_lastAuthDiagnostics,
                'phase': 'remote_check_after_local_success',
                'requestedTenant': requestedTenant,
                'username': username,
              };
            });
            final backendResponse = await BackendService.authenticateStaff(
              username: username,
              pin: password,
              tenantId: requestedTenant,
            );
            onlineResponse = backendResponse;
            _lastAuthDiagnostics =
                BackendService.staffAuthenticationDiagnostics(backendResponse) ??
                backendResponse;
            if (BackendService.isAuthoritativeStaffAuthenticationRejection(
                backendResponse)) {
              staff = null;
              _lastAuthSummary =
                  'Remote rejection (authoritative): ${_backendErrorSummary(backendResponse)}';
            } else if (backendResponse?['_transportFailure'] == true ||
                backendResponse == null ||
                backendResponse.isEmpty) {
              _lastAuthSummary =
                  'Remote auth unavailable; kept locally verified staff session (${_backendErrorSummary(backendResponse)})';
            } else {
              final merged = await _mergeOnlineStaff(backendResponse, staff,
                  username: username,
                  pin: password,
                  requestedTenant: requestedTenant);
              if (merged != null) staff = merged;
              _lastAuthSummary = 'Remote auth checked/merged successfully';
            }
          } catch (e, st) {
            _lastAuthSummary =
                'Remote auth threw; kept locally verified staff session: ${e.runtimeType}: $e';
            _lastAuthDiagnostics = <String, dynamic>{
              'phase': 'remote_check_after_local_success_exception',
              'exceptionType': e.runtimeType.toString(),
              'exception': e.toString(),
              'stackTrace': st.toString(),
              'backendUrl': BackendService.backendUrl,
              'endpoint': '${BackendService.backendUrl}/tenant/staff/authenticate',
              'tenantId': requestedTenant,
            };
          }
        }
      } else {
        if (!mounted) return;
        setState(() {
          _lastAuthSummary = 'Requesting remote staff authentication';
          _lastAuthDiagnostics = <String, dynamic>{
            ...?_lastAuthDiagnostics,
            'phase': 'remote_auth_without_local_verification',
            'requestedTenant': requestedTenant,
            'username': username,
          };
        });
        final backendResponse = await BackendService.authenticateStaff(
          username: username,
          pin: password,
          tenantId: requestedTenant,
        );
        onlineResponse = backendResponse;
        _lastAuthDiagnostics =
            BackendService.staffAuthenticationDiagnostics(backendResponse) ??
            backendResponse;
        if (backendResponse?['_transportFailure'] == true) {
          staff = null;
          await AuthService.recordFailure(userKey);
          _lastAuthSummary =
              'Remote auth transport/server failure: ${_backendErrorSummary(backendResponse)}';
        } else {
          staff = await _mergeOnlineStaff(backendResponse, null,
              username: username,
              pin: password,
              requestedTenant: requestedTenant);
          if (staff == null) {
            await AuthService.recordFailure(userKey);
            _lastAuthSummary =
                BackendService.isAuthoritativeStaffAuthenticationRejection(
                        backendResponse)
                    ? 'Remote rejection (authoritative): ${_backendErrorSummary(backendResponse)}'
                    : 'Remote auth returned no usable staff payload: ${_backendErrorSummary(backendResponse)}';
          } else {
            await AuthService.recordSuccess(userKey);
            _lastAuthSummary = 'Remote auth succeeded';
          }
        }
      }

      if (staff == null) {
        if (!mounted) return;
        setState(() {
          _error = _formatStaffAuthError(
            backendResponse: onlineResponse,
            fallback: AppLocalizations.of(context).loginWrongCredentials,
          );
        });
        return;
      }

      if (!mounted) return;
      final int staffId =
          staff.id ?? context.read<AppState>().rememberedStaffId ?? 0;
      final sessionToken = onlineResponse?['session_token'];
      if (sessionToken is String &&
          sessionToken.isNotEmpty &&
          staff.id != null) {
        await StaffCredentialCache.storeSessionToken(staff.id!, sessionToken);
      }
      await StaffCredentialCache.cacheStaffCredentials(
        staffId,
        username,
        password,
      );
      if (!mounted) return;
      await context.read<AppState>().rememberStaff(staff);
      if (!mounted) return;
      context.read<AppState>().signInAsStaff(staff);
      if (onlineResponse?['session_token'] is String &&
          staff.id != null &&
          !await StaffCredentialCache.pinPromptSeen(staff.id!)) {
        await StaffCredentialCache.markPinPromptSeen(staff.id!);
        if (!mounted) return;
        final changeNow = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Keep your PIN private'),
            content: const Text(
                'For your security, change the temporary or shared PIN now. Do not share your staff PIN with anyone, including the owner.'),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Later')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Change PIN')),
            ],
          ),
        );
        if (changeNow == true && mounted) {
          await showStaffPinChangeDialog(context, context.read<AppState>());
        }
      }
    } catch (e, st) {
      if (!mounted) return;
      final Map<String, dynamic> diagnostics = <String, dynamic>{
        'phase': 'submit_exception',
        'mode': kIsWeb ? 'web_diagnostic' : 'native',
        'backendUrl': BackendService.backendUrl,
        'endpoint': '${BackendService.backendUrl}/tenant/staff/authenticate',
        'exceptionType': e.runtimeType.toString(),
        'exception': e.toString(),
        'stackTrace': st.toString(),
        'note': kIsWeb
            ? 'Web diagnostic mode: local DB/session operations are skipped.'
            : null,
      };
      if (kDebugMode) {
        debugPrint('[StaffLogin] submit exception: ${e.runtimeType}: $e');
        debugPrint(st.toString());
      }
      setState(() {
        _lastAuthDiagnostics = diagnostics;
        _lastAuthSummary =
            'App exception during staff login: ${e.runtimeType}: $e';
        _error =
            '${AppLocalizations.of(context).loginNetworkError}\nApp error: ${e.runtimeType}: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatStaffAuthError({
    required Map<String, dynamic>? backendResponse,
    required String fallback,
    bool detailed = false,
  }) {
    final diagnostics =
        BackendService.staffAuthenticationDiagnostics(backendResponse);
    final status = diagnostics?['statusCode'];
    final data = diagnostics?['responseData'];
    String? detail;
    if (data is Map) {
      final dynamic message =
          data['error'] ?? data['message'] ?? data['detail'] ?? data['code'];
      if (message != null) detail = message.toString();
    } else if (data is String && data.trim().isNotEmpty) {
      detail = data.trim();
    } else if (diagnostics?['message'] != null) {
      detail = diagnostics!['message'].toString();
    }
    final bool transport = backendResponse?['_transportFailure'] == true;
    if (transport) {
      final String base = detail == null || detail.isEmpty
          ? 'Could not reach backend for staff authentication.'
          : 'Could not reach backend for staff authentication: $detail';
      return status == null ? base : '$base (HTTP $status)';
    }
    final bool rejected =
        BackendService.isAuthoritativeStaffAuthenticationRejection(
      backendResponse,
    );
    if (rejected && !detailed) {
      return fallback;
    }
    if (status != null || detail != null) {
      final List<String> parts = <String>[fallback];
      if (status != null) parts.add('HTTP $status');
      if (detail != null && detail.isNotEmpty && detail != fallback) {
        parts.add(detail);
      }
      return parts.join(' • ');
    }
    return fallback;
  }

  String _backendErrorSummary(Map<String, dynamic>? backendResponse) {
    final diagnostics =
        BackendService.staffAuthenticationDiagnostics(backendResponse);
    if (diagnostics == null || diagnostics.isEmpty) {
      if (backendResponse == null) return 'no response';
      if (backendResponse['_emptyResponse'] == true) return 'empty response body';
      return 'no diagnostics';
    }
    final status = diagnostics['statusCode'];
    final detail = _backendErrorDetails(diagnostics);
    final type = diagnostics['dioType'] ?? diagnostics['exceptionType'];
    final parts = <String>[
      if (status != null) 'HTTP $status',
      if (type != null && type.toString().isNotEmpty) 'type=$type',
      if (detail != null && detail.isNotEmpty) detail,
    ];
    return parts.isEmpty ? 'no backend error details' : parts.join(' • ');
  }

  String? _backendErrorDetails(Map<String, dynamic>? diagnosticsOrResponse) {
    if (diagnosticsOrResponse == null) return null;
    final Map<String, dynamic> diagnostics =
        BackendService.staffAuthenticationDiagnostics(diagnosticsOrResponse) ??
            diagnosticsOrResponse;
    final data = diagnostics['responseData'];
    String? detail;
    if (data is Map) {
      final dynamic message = data['error'] ??
          data['message'] ??
          data['detail'] ??
          data['code'] ??
          data['reason'];
      if (message != null) detail = message.toString();
    } else if (data is String && data.trim().isNotEmpty) {
      detail = data.trim();
    }
    detail ??= diagnostics['message']?.toString();
    detail ??= diagnostics['error']?.toString();
    detail ??= diagnostics['exception']?.toString();
    if (detail == null || detail.trim().isEmpty) return null;
    return detail.trim();
  }

  String? _appErrorDetails() {
    final diagnostics = _lastAuthDiagnostics;
    if (diagnostics == null) return null;
    final exception = diagnostics['exception']?.toString();
    final exceptionType = diagnostics['exceptionType']?.toString();
    final phase = diagnostics['phase']?.toString();
    if (exception == null && exceptionType == null) return null;
    final parts = <String>[
      if (phase != null && phase.isNotEmpty) 'phase=$phase',
      if (exceptionType != null && exceptionType.isNotEmpty) exceptionType,
      if (exception != null && exception.isNotEmpty) exception,
    ];
    return parts.join(' • ');
  }

  String _formatDiagnosticsForDisplay(Map<String, dynamic> diagnostics) {
    try {
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(diagnostics);
    } catch (_) {
      return diagnostics.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.all(spacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    OnboardStyle.header(
                      context: context,
                      onSignIn: () => context.go(Routes.welcome),
                      colors: colors,
                      spacing: spacing,
                      type: type,
                    ),
                    SizedBox(height: spacing.lg),
                    OnboardStyle.window(
                      context: context,
                      image: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              colors.surface,
                              colors.surfaceSunken
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: Icon(Icons.person_outline,
                              size: 56, color: colors.accent),
                        ),
                      ),
                      badgeIcon: Icons.person_outline,
                      label: 'STAFF',
                      title: l10n.staffLoginTitle,
                      body: _activeShopName != null
                          ? 'Signing in to $_activeShopName'
                          : 'Sign in to your shop',
                      type: type,
                      colors: colors,
                      spacing: spacing,
                    ),
                    SizedBox(height: spacing.lg),
                    if (_shopsLoaded) ...<Widget>[
                      TextFormField(
                        controller: _shopIdController,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.none,
                        decoration: const InputDecoration(
                          labelText: 'Shop ID',
                          helperText: 'Ask the owner for the verified shop ID',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                        validator: (String? value) {
                          final String v = (value ?? '').trim();
                          if (_shops.isEmpty && v.isEmpty) {
                            return 'Shop ID is required on a new device';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: spacing.md),
                    ],
                    TextFormField(
                      controller: _usernameController,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.text,
                      textCapitalization: TextCapitalization.none,
                      autofillHints: const <String>[AutofillHints.username],
                      decoration: InputDecoration(
                        labelText: l10n.staffUsernameLabel,
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                      validator: (String? value) =>
                          (value == null || value.trim().isEmpty)
                              ? l10n.fieldRequired('') as String?
                              : null,
                    ),
                    SizedBox(height: spacing.md),
                    TextFormField(
                      controller: _passwordController,
                      textInputAction: TextInputAction.done,
                      obscureText: _obscurePassword,
                      keyboardType: TextInputType.number,
                      autofillHints: const <String>[AutofillHints.password],
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(PinRules.staffLoginMaxLength),
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.staffPasswordLabel,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (String? value) {
                        final String pin = (value ?? '').trim();
                        if (pin.isEmpty) {
                          return l10n.fieldRequired('') as String?;
                        }
                        if (!PinRules.isStaffLoginPin(pin)) {
                          return l10n.validationPinMustBeFourOrSixDigits;
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    SizedBox(height: spacing.md),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: _loading ? null : _requestForgottenPin,
                        child: Text(l10n.staffForgotPinNotifyOwner),
                      ),
                    ),
                    if (_error != null)
                      PersistentBanner(
                        message: _error!,
                        icon: Icons.error_outline,
                        tone: StatusTone.danger,
                      ),
                    if (_lastAuthSummary != null || _lastAuthDiagnostics != null)
                      Padding(
                        padding: EdgeInsets.only(top: spacing.md),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(spacing.md),
                          decoration: BoxDecoration(
                            color: colors.surfaceSunken,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.outline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Staff login diagnostics',
                                style: type.titleSmall?.copyWith(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: spacing.xs),
                              Text(
                                'Backend: ${BackendService.backendUrl}',
                                style: type.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              if (_lastAuthSummary != null) ...<Widget>[
                                SizedBox(height: spacing.xs),
                                Text(
                                  _lastAuthSummary!,
                                  style: type.bodyMedium?.copyWith(
                                    color: colors.onSurface,
                                  ),
                                ),
                              ],
                              if (_backendErrorDetails(_lastAuthDiagnostics) !=
                                  null) ...<Widget>[
                                SizedBox(height: spacing.xs),
                                SelectableText(
                                  'Backend error: ${_backendErrorDetails(_lastAuthDiagnostics)}',
                                  style: type.bodySmall?.copyWith(
                                    color: colors.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (_appErrorDetails() != null) ...<Widget>[
                                SizedBox(height: spacing.xs),
                                SelectableText(
                                  'App error: ${_appErrorDetails()}',
                                  style: type.bodySmall?.copyWith(
                                    color: colors.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (_lastAuthDiagnostics != null) ...<Widget>[
                                if (_lastAuthDiagnostics!['statusCode'] != null ||
                                    _lastAuthDiagnostics!['classification'] !=
                                        null ||
                                    _lastAuthDiagnostics!['dioType'] != null ||
                                    _lastAuthDiagnostics!['phase'] != null) ...<Widget>[
                                  SizedBox(height: spacing.xs),
                                  SelectableText(
                                    [
                                      if (_lastAuthDiagnostics!['phase'] != null)
                                        'phase=${_lastAuthDiagnostics!['phase']}',
                                      if (_lastAuthDiagnostics!['classification'] !=
                                          null)
                                        'classification=${_lastAuthDiagnostics!['classification']}',
                                      if (_lastAuthDiagnostics!['statusCode'] !=
                                          null)
                                        'status=${_lastAuthDiagnostics!['statusCode']}',
                                      if (_lastAuthDiagnostics!['dioType'] != null)
                                        'dioType=${_lastAuthDiagnostics!['dioType']}',
                                    ].join(' • '),
                                    style: type.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                SizedBox(height: spacing.sm),
                                SelectableText(
                                  _formatDiagnosticsForDisplay(
                                    _lastAuthDiagnostics!,
                                  ),
                                  style: type.bodySmall?.copyWith(
                                    color: colors.onSurface,
                                    fontFamily: 'monospace',
                                    height: 1.35,
                                  ),
                                ),
                              ],
                              if (kIsWeb) ...<Widget>[
                                SizedBox(height: spacing.sm),
                                Text(
                                  'Web mode: remote staff authentication test only. Run with `flutter run -d chrome --dart-define=BACKEND_URL=https://duka-pos-backend.brianbmk332.workers.dev` to point at production.',
                                  style: type.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    SizedBox(height: spacing.md),
                    OnboardStyle.primaryButton(
                      context: context,
                      onPressed: _loading ? null : _submit,
                      label:
                          _loading ? 'Signing in...' : l10n.loginSignInAction,
                      colors: colors,
                      spacing: spacing,
                    ),
                    SizedBox(height: spacing.md),
                    OnboardStyle.link(
                      context: context,
                      onPressed:
                          _loading ? null : () => context.go(Routes.login),
                      label: l10n.backToPinPadAction,
                      colors: colors,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
