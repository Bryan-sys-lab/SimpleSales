import 'dart:async';

import 'package:flutter/material.dart';
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
import '../services/workspace_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../ui/onboarding_style.dart';

/// The username + password entry point for staff.
///
/// Redesigned to match the inspiration: dark canvas, emerald accent,
/// media window header, and styled actions.
class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key});

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
  List<LocalShop> _shops = const <LocalShop>[];
  bool _shopChosen = false;
  bool _askingShop = false;
  bool _shopsLoaded = false;
  String? _activeShopName;

  bool get _needsShopId => _shopsLoaded && _shops.isEmpty;

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
        title: const Text('Choose shop'),
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
            child: const Text('Cancel'),
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
    return DatabaseHelper.instance.mergeAuthenticatedStaff(
      remoteId: remoteId,
      username: username,
      name: staffMap['name'] as String? ?? fallback?.name ?? username,
      role: staffMap['role'] as String? ?? fallback?.role ?? 'cashier',
      pinHash: fallback?.pinHash ?? await AuthService.hashPin(pin),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _loading) return;
    if (!await _ensureShopSelected()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final String username = _usernameController.text.trim();
      final String password = _passwordController.text;
      final String? requestedTenant = _needsShopId
          ? _shopIdController.text.trim().toLowerCase()
          : null;
      if (_needsShopId && (requestedTenant == null || requestedTenant.isEmpty)) {
        setState(() => _error = 'Enter the shop ID supplied by the owner.');
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

      final List<Staff> localStaff = await DatabaseHelper.instance.getStaff();
      Staff? staff = localStaff.cast<Staff?>().firstWhere(
            (Staff? s) => s?.username?.toLowerCase() == username.toLowerCase(),
            orElse: () => null,
          );
      if (staff != null &&
          !await AuthService.verifyPin(password, staff.pinHash)) {
        await AuthService.recordFailure(userKey);
        staff = null;
      } else if (staff != null) {
        await AuthService.recordSuccess(userKey);
        final backendResponse = await BackendService.authenticateStaff(
          username: username,
          pin: password,
          tenantId: requestedTenant,
        );
        staff = await _mergeOnlineStaff(backendResponse, staff,
            username: username,
            pin: password,
            requestedTenant: requestedTenant);
      } else {
        final backendResponse = await BackendService.authenticateStaff(
          username: username,
          pin: password,
          tenantId: requestedTenant,
        );
        staff = await _mergeOnlineStaff(backendResponse, null,
            username: username,
            pin: password,
            requestedTenant: requestedTenant);
        if (staff == null) {
          await AuthService.recordFailure(userKey);
        } else {
          await AuthService.recordSuccess(userKey);
        }
      }

      if (staff == null) {
        if (!mounted) return;
        setState(() {
          _error = AppLocalizations.of(context).loginWrongCredentials;
        });
        return;
      }

      if (!mounted) return;
      final int staffId =
          staff.id ?? context.read<AppState>().rememberedStaffId ?? 0;
      await StaffCredentialCache.cacheStaffCredentials(
        staffId,
        username,
        password,
      );
      if (!mounted) return;
      await context.read<AppState>().rememberStaff(staff);
      if (!mounted) return;
      context.read<AppState>().signInAsStaff(staff);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context).loginNetworkError;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
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
                      image: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[Color(0xFF0B0F14), Color(0xFF11161D)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: Icon(Icons.person_outline, size: 56, color: Color(0xFF4ADE7E)),
                        ),
                      ),
                      badgeIcon: Icons.person_outline,
                      label: 'STAFF',
                      title: l10n.staffLoginTitle,
                      body: _activeShopName != null ? 'Signing in to $_activeShopName' : 'Sign in to your shop',
                      type: type,
                      colors: colors,
                      spacing: spacing,
                    ),
                    SizedBox(height: spacing.lg),
                    if (_needsShopId) ...<Widget>[
                      TextFormField(
                        controller: _shopIdController,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.none,
                        decoration: const InputDecoration(
                          labelText: 'Shop ID',
                          helperText: 'Ask the owner for the verified shop ID',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                        validator: (String? value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Shop ID is required on a new device'
                                : null,
                      ),
                      SizedBox(height: spacing.md),
                    ],
                    TextFormField(
                      controller: _usernameController,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.text,
                      textCapitalization: TextCapitalization.none,
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
                      decoration: InputDecoration(
                        labelText: l10n.staffPasswordLabel,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
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
                      validator: (String? value) =>
                          (value == null || value.isEmpty)
                              ? l10n.fieldRequired('') as String?
                              : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    SizedBox(height: spacing.md),
                    if (_error != null)
                      PersistentBanner(
                        message: _error!,
                        icon: Icons.error_outline,
                        tone: StatusTone.danger,
                      ),
                    SizedBox(height: spacing.md),
                    OnboardStyle.primaryButton(
                      context: context,
                      onPressed: _loading ? null : _submit,
                      label: _loading ? 'Signing in...' : l10n.loginSignInAction,
                      colors: colors,
                      spacing: spacing,
                    ),
                    SizedBox(height: spacing.md),
                    OnboardStyle.link(
                      context: context,
                      onPressed: _loading ? null : () => context.go(Routes.login),
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
