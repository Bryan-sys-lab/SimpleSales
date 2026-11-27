import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_brand.dart';
import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../routing/app_stage_controller.dart';
import '../routing/routes.dart';
import '../services/app_stage.dart';
import '../services/app_state.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/dialogs/pin_reset_dialog.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../ui/onboarding_style.dart';
import '../utils/pin_rules.dart';
import '../services/workspace_service.dart';

/// The owner's local PIN sign-in.
///
/// Redesigned to match the product palette: forest primary, electric accent,
/// brand header, PIN field, and styled actions. Staff use the separate
/// shop-ID sign-in so their activity cannot be attributed to the owner.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _OwnerState { loading, unavailable, ready }

class _LoginScreenState extends State<LoginScreen> {
  int get _pinLength => PinRules.adminLength;

  List<LocalShop> _shops = <LocalShop>[];

  bool _choosingShop = false;

  final TextEditingController _pin = TextEditingController();

  final FocusNode _pinFocus = FocusNode();

  String? _error;
  bool _loading = true;

  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Owner? get _owner => context.watch<AppState>().owner;

  _OwnerState get _ownerState {
    if (_loading) return _OwnerState.loading;
    if (_owner == null) return _OwnerState.unavailable;
    return _OwnerState.ready;
  }

  bool _shopChosen = false;

  bool _askingShop = false;

  Future<void> _load() async {
    final List<LocalShop> shops = await WorkspaceServiceShops.localShops();
    if (!mounted) return;
    setState(() {
      _shops = shops;
      _choosingShop = false;
      _loading = false;
    });
  }

  Future<void> _chooseShop(LocalShop shop) async {
    if (_verifying) return;
    final AppState state = context.read<AppState>();
    setState(() {
      _choosingShop = false;
      _shopChosen = true;
      _loading = true;
      _error = null;
    });
    await state.switchWorkspace(shop.workspaceKey, signIn: false);
    if (!mounted) return;
    _pin.clear();
    await _load();
  }

  void _onPinChanged(String value) {
    if (_verifying) return;
    if (_error != null) setState(() => _error = null);
    if (value.length == _pinLength) {
      HapticTheme.of(context).fire(HapticEvent.select);
      _tryLogin();
    }
  }

  Future<void> _forgotPin() async {
    final AppState state = context.read<AppState>();
    final Owner? owner = state.owner;
    if (owner == null || owner.email.trim().isEmpty) {
      if (!mounted) return;
      _refuse(AppLocalizations.of(context).pinResetNoEmail);
      return;
    }
    final result = await showDialog<PinResetResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinResetDialog(ownerEmail: owner.email),
    );
    if (!mounted || result == null || !result.completed) return;
    setState(() => _error = null);
    _pin.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).pinResetDone)),
    );
  }

  Future<LocalShop?> _askWhichShop() {
    final AppSpacing spacing = AppSpacing.of(context);
    return showDialog<LocalShop>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext).loginChooseShopTitle),
        contentPadding: EdgeInsets.fromLTRB(
          spacing.lg,
          spacing.md,
          spacing.lg,
          spacing.sm,
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: (_shops.length * 64).clamp(64, 320).toDouble(),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _shops.length,
            separatorBuilder: (_, __) => SizedBox(height: spacing.sm),
            itemBuilder: (BuildContext context, int index) => _ShopTile(
              shop: _shops[index],
              onTap: () => Navigator.of(dialogContext).pop(_shops[index]),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppLocalizations.of(dialogContext).actionCancel),
          ),
        ],
      ),
    );
  }

  Future<void> _tryLogin() async {
    final AppState state = context.read<AppState>();
    const String userKey = AuthService.ownerLockoutKey;

    if (_shops.length > 1 && !_shopChosen && !_askingShop) {
      _askingShop = true;
      late final LocalShop? shop;
      try {
        shop = await _askWhichShop();
      } finally {
        _askingShop = false;
      }
      if (shop == null) {
        if (mounted) _pin.clear();
        return;
      }
      if (!mounted) return;
      await state.switchWorkspace(shop.workspaceKey, signIn: false);
      if (!mounted) return;
      _shopChosen = true;
      await _load();
      if (!mounted) return;
      if (state.owner == null) {
        _refuse(AppLocalizations.of(context).loginNotInThisShop);
        return;
      }
    }

    setState(() => _verifying = true);
    try {
      if (await AuthService.isTillLockedOut()) {
        final Duration? remaining = await AuthService.tillLockoutRemaining();
        if (!mounted) return;
        _refuse(
          'Too many wrong PINs on this till. '
          'Try again in ${remaining?.inSeconds ?? 0}s.',
        );
        return;
      }

      if (await AuthService.isLockedOut(userKey)) {
        final Duration? remaining = await AuthService.lockoutRemaining(userKey);
        if (!mounted) return;
        _refuse(
          'Too many wrong PINs. Try again in ${remaining?.inSeconds ?? 0}s.',
        );
        return;
      }

      final Owner? owner = state.owner;
      if (owner == null) {
        if (!mounted) return;
        _refuse(AppLocalizations.of(context).loginNotInThisShop);
        return;
      }
      final String pin = _pin.text;
      final bool ok = await AuthService.verifyPin(pin, owner.pinHash);
      if (!mounted) return;
      if (ok) {
        await AuthService.recordSuccess(userKey);
        final String hash = owner.pinHash;
        if (AuthService.needsUpgrade(hash)) {
          await DatabaseHelper.instance
              .updateOwnerPin(await AuthService.hashPin(pin));
        }
        state.signInAsOwner();
        return;
      }

      await AuthService.recordFailure(userKey);
      final bool lockedNow = await AuthService.isLockedOut(userKey);
      if (!mounted) return;
      _refuse(
        lockedNow
            ? 'Too many wrong PINs. '
                'Locked for ${AuthService.lockoutDuration.inSeconds}s.'
            : 'Wrong PIN',
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _refuse(String message) {
    HapticTheme.of(context).fire(HapticEvent.reject);
    setState(() => _error = message);
    _pin.clear();
  }

  void _setUpShop() {
    HapticTheme.of(context).fire(HapticEvent.select);
    context.read<AppStageController>().choose(AppChooserIntent.setUp);
    context.go(Routes.setup);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    final Owner? owner = _owner;
    final String shopName = owner?.shopName ?? SimplePosBrand.appName;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kPadWidth),
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  spacing.xl,
                  spacing.lg,
                  spacing.xl,
                  spacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    OnboardStyle.header(
                      context: context,
                      onSignIn: () => context.go(Routes.welcome),
                      colors: colors,
                      spacing: spacing,
                      type: type,
                    ),
                    SizedBox(height: spacing.lg),
                    // Media window style header
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
                          child: Icon(Icons.lock_outline,
                              size: 56, color: colors.accent),
                        ),
                      ),
                      badgeIcon: Icons.lock_outline,
                      label: 'SIGN IN',
                      title: shopName,
                      body: 'Owner sign-in only. Staff use their shop ID.',
                      type: type,
                      colors: colors,
                      spacing: spacing,
                    ),
                    SizedBox(height: spacing.lg),
                    _choosingShop
                        ? _ShopChooser(
                            shops: _shops,
                            onChosen: _chooseShop,
                          )
                        : switch (_ownerState) {
                            _OwnerState.loading => const _OwnerLoading(),
                            _OwnerState.unavailable => _NoAccountsPanel(
                                onSetUp: _setUpShop,
                                onRecover: () =>
                                    context.go(Routes.accountRecovery),
                                onStaffLogin: () =>
                                    context.go(Routes.staffLogin),
                              ),
                            _OwnerState.ready => SurfaceCard(
                                child: ListTile(
                                  leading:
                                      const Icon(Icons.verified_user_outlined),
                                  title: Text(owner?.name ?? ''),
                                  subtitle: const Text('Shop owner'),
                                ),
                              ),
                          },
                    if (!_choosingShop && _shops.length > 1)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _choosingShop = true),
                          icon: const Icon(Icons.storefront_outlined),
                          label: Text(l10n.loginChooseShopAction),
                        ),
                      ),
                    if (_error != null) ...<Widget>[
                      SizedBox(height: spacing.md),
                      PersistentBanner(
                        message: _error!,
                        icon: Icons.lock_outline,
                        tone: StatusTone.danger,
                      ),
                    ],
                    SizedBox(height: spacing.md),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _pin,
                      builder: (
                        BuildContext context,
                        TextEditingValue value,
                        Widget? field,
                      ) =>
                          Semantics(
                        container: true,
                        liveRegion: true,
                        label: l10n.loginFilledPINDigitsEntered(
                          value.text.length.clamp(0, _pinLength),
                          _pinLength,
                        ),
                        child: ExcludeSemantics(child: field),
                      ),
                      child: TextField(
                        controller: _pin,
                        focusNode: _pinFocus,
                        autofocus: true,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(_pinLength),
                        ],
                        onChanged: _onPinChanged,
                        onSubmitted: (_) => _tryLogin(),
                        enabled: !_verifying,
                        decoration: InputDecoration(
                          labelText: l10n.loginPinLabel,
                          hintText: '0' * _pinLength,
                        ),
                      ),
                    ),
                    SizedBox(height: spacing.sm),
                    Text(
                      _verifying ? 'Checking this PIN' : '',
                      textAlign: TextAlign.center,
                      style: type.labelSmall
                          ?.copyWith(color: colors.onSurfaceMuted),
                    ),
                    if (owner != null && owner.email.trim().isNotEmpty)
                      TextButton(
                        onPressed: _verifying ? null : _forgotPin,
                        child: Text(AppLocalizations.of(context)
                            .settingsForgotPinAction),
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

class _ShopChooser extends StatelessWidget {
  const _ShopChooser({required this.shops, required this.onChosen});

  final List<LocalShop> shops;
  final Future<void> Function(LocalShop shop) onChosen;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(l10n.loginChooseShopTitle, style: type.titleMedium),
        ),
        SizedBox(height: spacing.xs),
        Text(
          l10n.loginChooseShopSubtitle(shops.length),
          style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
        ),
        SizedBox(height: spacing.md),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: shops.length,
          separatorBuilder: (_, __) => SizedBox(height: spacing.sm),
          itemBuilder: (BuildContext context, int index) {
            final LocalShop shop = shops[index];
            return _ShopTile(
              shop: shop,
              onTap: () => onChosen(shop),
            );
          },
        ),
      ],
    );
  }
}

class _ShopTile extends StatelessWidget {
  const _ShopTile({required this.shop, required this.onTap});

  final LocalShop shop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Material(
      color: colors.surface,
      borderRadius: AppShapes.of(context).controlRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppShapes.of(context).controlRadius,
        child: Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Row(
            children: <Widget>[
              Icon(Icons.storefront_outlined, color: colors.onSurfaceMuted),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(shop.shopName, style: type.titleSmall),
                    SizedBox(height: spacing.xs),
                    Text(
                      shop.isBackendLinked
                          ? l10n.settingsLinkedShop
                          : l10n.settingsLocalOnlyShop,
                      style: type.bodySmall
                          ?.copyWith(color: colors.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerLoading extends StatelessWidget {
  const _OwnerLoading();

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Loading shop owner account',
        child: ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.all(spacing.lg),
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ),
    );
  }
}

class _NoAccountsPanel extends StatelessWidget {
  const _NoAccountsPanel({
    required this.onSetUp,
    required this.onRecover,
    required this.onStaffLogin,
  });

  final VoidCallback onSetUp;
  final VoidCallback onRecover;
  final VoidCallback onStaffLogin;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Center(
      child: SingleChildScrollView(
        child: SurfaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(
                Icons.person_off_outlined,
                size: 32,
                color: AppColors.of(context).onSurfaceMuted,
                semanticLabel: '',
              ),
              SizedBox(height: spacing.sm),
              Semantics(
                header: true,
                child: Text(
                  AppLocalizations.of(context).loginNoAccountsYetTitle,
                  textAlign: TextAlign.center,
                  style: type.titleMedium,
                ),
              ),
              SizedBox(height: spacing.sm),
              Text(
                'Set up the owner account on this device. Staff sign in '
                'separately with their shop ID, username, and PIN.',
                textAlign: TextAlign.center,
                style: type.bodyMedium,
              ),
              SizedBox(height: spacing.lg),
              OutlinedButton.icon(
                onPressed: onStaffLogin,
                icon: const Icon(Icons.badge_outlined),
                label: Text(l10n.chooserSignInAsStaffAction),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: onSetUp,
                child: Text(l10n.settingsShopNotOnDevice),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onRecover,
                icon: const Icon(Icons.cloud_download_outlined),
                label: Text(l10n.accountRecoveryAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _kPadWidth = 460;
