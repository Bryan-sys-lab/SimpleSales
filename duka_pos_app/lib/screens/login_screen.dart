import 'package:flutter/material.dart';
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
import '../services/roles.dart';
import '../services/staff_credential_cache.dart';
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

/// The PIN pad. The only way into the shop.
///
/// Redesigned to match the inspiration: dark canvas, emerald accent,
/// brand header, roster, PIN field, and styled actions.
class LoginScreen extends StatefulWidget {
  const LoginScreen({this.staffLoader, super.key});

  final Future<List<Staff>> Function()? staffLoader;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _RosterState { loading, noAccounts, ready }

class _LoginScreenState extends State<LoginScreen> {
  static const String _ownerValue = '__owner__';

  int get _pinLength =>
      _selected == _ownerValue ? PinRules.adminLength : PinRules.staffLength;

  List<Staff> _staff = [];

  List<LocalShop> _shops = <LocalShop>[];

  bool _choosingShop = false;

  String? _selected; // '__owner__' or 'staff:<id>'

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

  static String _tagFor(Staff staff) =>
      staff.id == null ? 'name:${staff.name}' : 'staff:${staff.id}';

  Staff? get _selectedStaff {
    final String? tag = _selected;
    if (tag == null || tag == _ownerValue) return null;
    if (tag.startsWith('staff:')) {
      final int? id = int.tryParse(tag.substring(6));
      if (id == null) return null;
      for (final Staff member in _staff) {
        if (member.id == id) return null;
      }
      return null;
    }
    if (tag.startsWith('name:')) {
      final String name = tag.substring(5);
      for (final Staff member in _staff) {
        if (member.name == name) return null;
      }
    }
    return null;
  }

  Owner? get _owner => context.watch<AppState>().owner;

  _RosterState get _rosterState {
    if (_loading) return _RosterState.loading;
    if (_owner == null && _staff.isEmpty) return _RosterState.noAccounts;
    return _RosterState.ready;
  }

  bool _shopChosen = false;

  bool _askingShop = false;

  Future<void> _load() async {
    final Owner? owner = context.read<AppState>().owner;
    final List<Staff> staff = await (widget.staffLoader?.call() ??
        DatabaseHelper.instance.getStaff());
    final List<LocalShop> shops = await WorkspaceServiceShops.localShops();
    if (!mounted) return;
    setState(() {
      _staff = staff;
      _shops = shops;
      _choosingShop = false;
      _selected = owner != null
          ? _ownerValue
          : (staff.isEmpty ? null : _tagFor(staff.first));
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

  void _selectIdentity(String? tag) {
    setState(() {
      _selected = tag;
      _error = null;
    });
    _pin.clear();
    HapticTheme.of(context).fire(HapticEvent.select);
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
    final String userKey = _selected ?? '';

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
      final bool personHere = userKey == _ownerValue ||
          _staff.any((Staff s) => _tagFor(s) == userKey);
      if (!personHere) {
        _refuse(AppLocalizations.of(context).loginNotInThisShop);
        return;
      }
      setState(() => _selected = userKey);
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

      bool ok = false;
      final Owner? owner = state.owner;
      final String pin = _pin.text;
      if (_selected == _ownerValue && owner != null) {
        ok = await AuthService.verifyPin(pin, owner.pinHash);
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
      } else {
        final Staff? staff = _selectedStaff;
        if (staff != null) {
          ok = await AuthService.verifyPin(pin, staff.pinHash);
          if (!ok && staff.id != null) {
            ok = await StaffCredentialCache.verifyCachedPin(staff.id!, pin);
          }
          if (!mounted) return;
          if (ok) {
            await AuthService.recordSuccess(userKey);
            if (AuthService.needsUpgrade(staff.pinHash) && staff.id != null) {
              await DatabaseHelper.instance
                  .updateStaffPin(staff.id!, await AuthService.hashPin(pin));
            }
            state.signInAsStaff(staff);
            return;
          }
        }
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
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kPadWidth),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                spacing.xl,
                spacing.lg,
                spacing.xl,
                spacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
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
                    image: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[Color(0xFF0B0F14), Color(0xFF11161D)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Icon(Icons.lock_outline, size: 56, color: Color(0xFF4ADE7E)),
                      ),
                    ),
                    badgeIcon: Icons.lock_outline,
                    label: 'SIGN IN',
                    title: shopName,
                    body: 'Enter your PIN to unlock the till',
                    type: type,
                    colors: colors,
                    spacing: spacing,
                  ),
                  SizedBox(height: spacing.lg),
                  Expanded(
                    child: _choosingShop
                        ? _ShopChooser(
                            shops: _shops,
                            onChosen: _chooseShop,
                          )
                        : switch (_rosterState) {
                            _RosterState.loading => const _RosterLoading(),
                            _RosterState.noAccounts => _NoAccountsPanel(
                                onSetUp: _setUpShop,
                              ),
                            _RosterState.ready => _WhoPicker(
                                ownerName: owner?.name,
                                staff: _staff,
                                selected: _selected,
                                onChanged: _selectIdentity,
                              ),
                          },
                  ),
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
                    ) => Semantics(
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
                    style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
                  ),
                  if (owner != null &&
                      owner.email.trim().isNotEmpty &&
                      (_selected == null || _selected == _ownerValue))
                    TextButton(
                      onPressed: _verifying ? null : _forgotPin,
                      child: Text(
                          AppLocalizations.of(context).settingsForgotPinAction),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}



// Keep existing supporting classes (_ShopChooser, _ShopTile, _RosterLoading,
// _NoAccountsPanel, _WhoPicker, _RosterRow, _WhoTile) unchanged for logic.
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
        Expanded(
          child: ListView.separated(
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

class _RosterLoading extends StatelessWidget {
  const _RosterLoading();

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Loading who can sign in on this till',
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
  const _NoAccountsPanel({required this.onSetUp});

  final VoidCallback onSetUp;

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
                'A shop admin sets this device up once. After that, everyone '
                'signs in here with the PIN their shop gave them.',
                textAlign: TextAlign.center,
                style: type.bodyMedium,
              ),
              SizedBox(height: spacing.lg),
              FilledButton(
                onPressed: onSetUp,
                child: Text(l10n.settingsShopNotOnDevice),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhoPicker extends StatelessWidget {
  const _WhoPicker({
    required this.ownerName,
    required this.staff,
    required this.selected,
    required this.onChanged,
  });

  final String? ownerName;
  final List<Staff> staff;
  final String? selected;
  final ValueChanged<String?> onChanged;

  Map<ShopRole, List<Staff>> get _byRole {
    final Map<ShopRole, List<Staff>> grouped = <ShopRole, List<Staff>>{};
    for (final Staff member in staff) {
      grouped
          .putIfAbsent(ShopRole.parse(member.role), () => <Staff>[])
          .add(member);
    }
    return grouped;
  }

  static String _tagFor(Staff staff) =>
      staff.id == null ? 'name:${staff.name}' : 'staff:${staff.id}';

  bool _sameTag(Staff member) {
    final String tag = _tagFor(member);
    return selected == tag ||
        (selected != null &&
            selected!.startsWith('name:') &&
            selected!.substring(5) == member.name);
  }

  List<_RosterRow> _rows(AppLocalizations l10n) {
    final Map<ShopRole, List<Staff>> byRole = _byRole;
    final List<Staff> chosen = staff.where(_sameTag).toList();
    final bool chosenOwner = selected == '__owner__' && ownerName != null;

    final Set<ShopRole> roles = <ShopRole>{
      ...byRole.keys,
      if (ownerName != null) ShopRole.admin,
    };
    final List<ShopRole> ordered =
        ShopRole.values.where(roles.contains).toList(growable: false);

    final List<_RosterRow> rows = <_RosterRow>[];
    for (final ShopRole role in ordered) {
      final String title = roleSectionTitle(l10n, role);
      if (ordered.length > 1) rows.add(_RosterRow.header(title));
      if (role == ShopRole.admin && ownerName != null) {
        rows.add(
          _RosterRow.person(
            name: ownerName!,
            roleLabel: ShopRole.admin.label,
            tag: '__owner__',
            selected: chosenOwner,
          ),
        );
      }
      for (final Staff member in byRole[role] ?? const <Staff>[]) {
        rows.add(
          _RosterRow.person(
            name: member.name,
            roleLabel: ShopRole.parse(member.role).label,
            tag: _tagFor(member),
            selected: chosen.contains(member),
          ),
        );
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    final List<Staff> chosen = staff.where(_sameTag).toList();
    final bool chosenOwner = selected == '__owner__' && ownerName != null;
    final bool hasChosen = chosenOwner || chosen.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(l10n.loginWhoAreYou, style: type.titleMedium),
        ),
        SizedBox(height: spacing.sm),
        Expanded(
          child: Builder(
            builder: (BuildContext context) {
              final List<_RosterRow> rows = _rows(AppLocalizations.of(context));
              return ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                itemBuilder: (BuildContext context, int index) {
                  final _RosterRow row = rows[index];
                  if (row.isHeader) {
                    return SectionHeader(
                      label: row.title!,
                      padding: EdgeInsetsDirectional.only(
                        top: spacing.sm,
                        bottom: spacing.xs,
                      ),
                    );
                  }
                  return _WhoTile(
                    key: ValueKey<String>(row.tag!),
                    name: row.name!,
                    roleLabel: row.roleLabel!,
                    selected: row.selected,
                    onTap: () => onChanged(row.tag),
                  );
                },
              );
            },
          ),
        ),
        if (hasChosen)
          Padding(
            padding: EdgeInsetsDirectional.only(top: spacing.sm),
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Signing in as ${chosenOwner ? ownerName : chosen.first.name}',
                textAlign: TextAlign.center,
                style: type.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RosterRow {
  const _RosterRow.header(this.title)
      : name = null,
        roleLabel = null,
        tag = null,
        selected = false;

  const _RosterRow.person({
    required this.name,
    required this.roleLabel,
    required this.tag,
    required this.selected,
  }) : title = null;

  final String? title;
  final String? name;
  final String? roleLabel;
  final String? tag;
  final bool selected;

  bool get isHeader => title != null;
}

class _WhoTile extends StatelessWidget {
  const _WhoTile({
    required this.name,
    required this.roleLabel,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String name;
  final String roleLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: spacing.sm),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: spacing.minTapTarget),
        child: Semantics(
          button: true,
          selected: selected,
          label: AppLocalizations.of(context).loginName(name, roleLabel),
          onTap: onTap,
          excludeSemantics: true,
          child: Material(
            color: selected ? colors.accentContainer : colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: shapes.controlRadius,
              side: BorderSide(
                color: selected ? colors.accent : colors.outline,
                width: selected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: spacing.md,
                  vertical: spacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      size: 20,
                      color: selected ? colors.accent : colors.onSurfaceMuted,
                    ),
                    SizedBox(width: spacing.md),
                    Expanded(
                      child: Text(
                        name,
                        style: selected
                            ? type.titleMedium
                                ?.copyWith(color: colors.onAccentContainer)
                            : type.bodyLarge,
                      ),
                    ),
                    SizedBox(width: spacing.sm),
                    Flexible(
                      child: Text(
                        roleLabel,
                        textAlign: TextAlign.end,
                        style: type.labelMedium?.copyWith(
                          color: selected
                              ? colors.onAccentContainer
                              : colors.onSurfaceMuted,
                        ),
                      ),
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

const double _kPadWidth = 460;

String roleSectionTitle(AppLocalizations l10n, ShopRole role) => switch (role) {
      ShopRole.admin => l10n.loginRoleAdmins,
      ShopRole.manager => l10n.loginRoleManagers,
      ShopRole.cashier => l10n.loginRoleCashiers,
    };
