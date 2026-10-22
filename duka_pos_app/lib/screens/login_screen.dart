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
import '../ui/components/screen_title.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../utils/pin_rules.dart';
import '../services/workspace_service.dart';

/// The PIN pad. The only way into the shop.
///
/// This is the highest-consequence screen in the app: every sale, every
/// report, and every price edit in the session is behind a PIN and the
/// identity it is checked against. So the pad is built for the two people
/// most likely to be using it badly rather than for the one person who will use
/// it perfectly:
///
///  * **A key is a key.** 44px minimum, a real `InkWell` with a real focus
///    node, and a semantics node that says what it is ("Digit 4"), not what it
///    looks like. Nothing here is a gesture-only target.
///  * **The identity is confirmable before the digits.** The roster is above the
///    pad and the selection is echoed under it, on a live region, so a mis-pick
///    is visible *and* announced before the digits are committed.
///  * **Failures are announced, not just coloured.** Every error is a live
///    region with a glyph and a sentence, because "Wrong PIN" as red text is
///    silence to a screen-reader user.
class LoginScreen extends StatefulWidget {
  const LoginScreen({this.staffLoader, super.key});

  /// Where the staff roster comes from.
  ///
  /// A SEAM, and the reason it exists is testability: reading
  /// `DatabaseHelper` from `initState` puts real file I/O inside the widget's
  /// lifecycle, which means this screen cannot be exercised by `testWidgets` at
  /// all — the fake async zone never lets the query resolve, so the test hangs
  /// rather than failing. That is a bad property for the screen where every
  /// keystroke, every label and every tap target most needs verifying.
  ///
  /// Defaults to the database. A test passes a list, and the screen behaves
  /// identically otherwise.
  final Future<List<Staff>> Function()? staffLoader;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Which of the three roster states this screen is in.
///
/// One switch, one state: a screen that carries `isLoading`, `hasStaff` and
/// `error` as three independent booleans renders a contradiction the moment two
/// of them disagree, which is exactly what happens between the roster query and
/// its result.
enum _RosterState { loading, noAccounts, ready }

class _LoginScreenState extends State<LoginScreen> {
  static const String _ownerValue = '__owner__';

  /// The length of the PIN being asked for.
  ///
  /// A staff member's PIN is four digits. The owner's is an ADMIN PIN, and an
  /// admin PIN is six — so the pad asks for six when the owner is the picked
  /// identity and four for anybody else.
  ///
  /// There is no third case and nothing to choose: the owner's PIN is six
  /// digits, everywhere it is asked for. The setup screen makes it six, the
  /// sheet that proves ownership asks for six, and the sign-in pad asks for
  /// six — so an owner has exactly one PIN, and it is the one the app expects.
  int get _pinLength =>
      _selected == _ownerValue ? PinRules.adminLength : PinRules.staffLength;

  List<Staff> _staff = [];

  /// The shops on this device.
  ///
  /// Read from the LOCAL registry, not from the backend: a shop that has
  /// never been online is still a shop on this phone, and it has to be
  /// sign-in-able without a network.
  List<LocalShop> _shops = <LocalShop>[];

  /// True while the person is choosing which shop to open.
  ///
  /// Only ever true when the phone holds MORE THAN ONE shop. With one shop
  /// there is nothing to choose, and a chooser over a single entry is a
  /// screen that makes the person tap something to get to where they were
  /// going anyway.
  bool _choosingShop = false;

  /// The identity currently picked, as a tag string.
  ///
  /// A tag rather than the display name because two staff can legitimately
  /// share a name, "Ali" on the counter and "Ali" doing deliveries, and matching
  /// the selection by name silently signed in the wrong one.
  String? _selected; // '__owner__' or 'staff:<id>'

  /// The PIN being typed.
  ///
  /// A controller rather than a string, because the PIN is now typed into a
  /// FIELD: the system's own numeric keyboard, not a keypad drawn by the app.
  ///
  /// The keypad it replaced was not better. It was four rows of keys that
  /// took half the screen of a phone that also has to show the roster, it
  /// could not be filled by a barcode scanner or a keyboard case, and it had
  /// to be maintained as a widget with its own hit targets, its own
  /// accessibility and its own layout at every text scale. The system's
  /// keyboard is faster, is already the right shape for a number, and comes
  /// with the user's own language and input method.
  final TextEditingController _pin = TextEditingController();

  final FocusNode _pinFocus = FocusNode();

  String? _error;
  bool _loading = true;

  /// True while a PIN is being checked.
  ///
  /// Without it, a person who types four digits again before the first answer
  /// lands starts a second verification, and two concurrent failures against
  /// the same lockout record count twice towards locking a till out.
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // The controller and the focus node hold native resources — a text
    // connection and an input connection — and neither is collected while the
    // screen is alive. A leak here is a leak on every sign-in.
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  /// Stable selection tag for a staff row.
  ///
  /// Prefers the id, because that is what the ledger keys attribution on.
  /// Falls back to the name only for a row that somehow has no id, which is
  /// then still unique enough to select, though not to attribute a sale to.
  static String _tagFor(Staff staff) =>
      staff.id == null ? 'name:${staff.name}' : 'staff:${staff.id}';

  Staff? get _selectedStaff {
    final String? tag = _selected;
    if (tag == null || tag == _ownerValue) return null;
    if (tag.startsWith('staff:')) {
      final int? id = int.tryParse(tag.substring(6));
      if (id == null) return null;
      for (final Staff member in _staff) {
        if (member.id == id) return member;
      }
      return null;
    }
    if (tag.startsWith('name:')) {
      final String name = tag.substring(5);
      for (final Staff member in _staff) {
        if (member.name == name) return member;
      }
    }
    return null;
  }

  /// The shop on this till, when there is one. A till whose shop record is
  /// missing must still render this screen: the router can reach the PIN pad
  /// without one, and dereferencing a null owner here used to be the difference
  /// between "no accounts" and a red screen.
  Owner? get _owner => context.watch<AppState>().owner;

  _RosterState get _rosterState {
    if (_loading) return _RosterState.loading;
    if (_owner == null && _staff.isEmpty) return _RosterState.noAccounts;
    return _RosterState.ready;
  }

  /// Whether the shop chooser has been shown and answered this session.
  ///
  /// `_load()` re-opens the chooser whenever the device holds more than one
  /// shop — which is right on the FIRST load, and wrong after a choice:
  /// `_chooseShop` calls `_load()` to read the new shop's roster, and the
  /// chooser slammed straight back down over it, so on a two-shop phone the
  /// staff roster was unreachable and nobody but the owner could sign in.
  /// Once the person has named a shop, the chooser stays put until the screen
  /// is rebuilt from scratch.
  bool _shopChosen = false;

  /// One shop question at a time.
  ///
  /// The question is asked from the PIN handler, and while it is open the pad
  /// is still live underneath it. A second submit would open a second dialog
  /// on top of the first, and choosing in the lower one would switch shops
  /// under the upper one. The flag makes the question single-flight.
  bool _askingShop = false;

  Future<void> _load() async {
    // Read before the await, never after it: context must not cross an async
    // gap, and the owner cannot change while this screen is being built, the
    // router only reaches the PIN pad once a shop exists.
    final Owner? owner = context.read<AppState>().owner;
    final List<Staff> staff = await (widget.staffLoader?.call() ??
        DatabaseHelper.instance.getStaff());
    // The shops on this device. Read here rather than in the build, because
    // the roster and the shop list have to agree about WHICH shop the roster
    // belongs to — and the only one that decides that is the active shop.
    final List<LocalShop> shops = await WorkspaceServiceShops.localShops();
    if (!mounted) return;
    setState(() {
      _staff = staff;
      _shops = shops;
      // The chooser is NOT opened on load.
      //
      // A till screen that opens on a shop list before anyone has touched it
      // reads as a setup step, and a person who came to type their PIN has to
      // get past a question they did not ask. The shop is asked for at the
      // moment it starts to MATTER — when the PIN is submitted and the app is
      // about to sign someone in — and the roster they see before that is
      // their own shop's, which is the shop they are standing in.
      _choosingShop = false;
      // Default to the owner only when there is one.
      _selected = owner != null
          ? _ownerValue
          : (staff.isEmpty ? null : _tagFor(staff.first));
      _loading = false;
    });
  }

  /// Opens the chosen shop, and signs in to it.
  ///
  /// The switch happens BEFORE the roster is read again, so the people on
  /// screen are that shop's people and nobody else's.
  Future<void> _chooseShop(LocalShop shop) async {
    if (_verifying) return;
    final AppState state = context.read<AppState>();
    setState(() {
      _choosingShop = false;
      _shopChosen = true;
      _loading = true;
      _error = null;
    });
    // `signIn: false` — this is a CHOOSER, not a sign-in. The person is on
    // their way to typing a PIN; signing them in as the owner here would
    // skip the very thing they came to do.
    await state.switchWorkspace(shop.workspaceKey, signIn: false);
    if (!mounted) return;
    _pin.clear();
    await _load();
  }

  /// The PIN field changed.
  ///
  /// It submits ITSELF when the fourth digit lands, because a PIN is a fixed
  /// length and the owner has nothing to press: the same reason the keypad
  /// submitted rather than waiting for an OK.
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

  /// Forgot PIN: a code emailed to the owner, then a new one.
  ///
  /// Only reachable for the OWNER. A cashier's PIN is the owner's to reset from
  /// Settings — handing a mailed reset to every staff identity would let any
  /// one of them take over the account the owner row protects.
  ///
  /// The owner is signed in on the existing session by the dialog, so no one
  /// has to unlock the till to get their PIN back: this is the whole reason the
  /// entry point is on this screen rather than in Settings.
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
      // Not dismissible by tapping outside: a half-finished reset would leave
      // a live code redeemable by whoever picks the phone up next.
      barrierDismissible: false,
      builder: (_) => PinResetDialog(ownerEmail: owner.email),
    );
    if (!mounted || result == null || !result.completed) return;
    // The PIN is new, so the pad clears and the owner types it fresh. Leaving
    // the old four digits in the dots would invite a fifth tap that submits
    // them as the new PIN.
    setState(() => _error = null);
    _pin.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).pinResetDone)),
    );
  }

  /// Asks which shop to sign in to, when this phone holds more than one.
  ///
  /// ## WHY AT SIGN-IN AND NOT ON ARRIVAL
  ///
  /// The roster and the PIN pad belong to a shop, so the shop has to be known
  /// before the PIN is checked — but asking on arrival makes every sign-in
  /// start with a menu, including the nine in ten that are for the shop the
  /// till is already in. Asking at the moment the PIN lands costs one tap only
  /// when there is genuinely something to choose, and it is the point where
  /// "which shop" changes the answer.
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
          // A phone with many shops still gets a bounded list, so the dialog
          // cannot grow past the screen and lose its own buttons.
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
    // Read before the await, never after it.
    final AppState state = context.read<AppState>();
    final String userKey = _selected ?? '';

    // Which shop? Only asked once per visit to this screen, and only when
    // there is more than one to choose from.
    if (_shops.length > 1 && !_shopChosen && !_askingShop) {
      _askingShop = true;
      late final LocalShop? shop;
      try {
        shop = await _askWhichShop();
      } finally {
        _askingShop = false;
      }
      if (shop == null) {
        // Cancelled: the digits stay typed, and the next tap tries again.
        if (mounted) _pin.clear();
        return;
      }
      if (!mounted) return;
      await state.switchWorkspace(shop.workspaceKey, signIn: false);
      if (!mounted) return;
      _shopChosen = true;
      await _load();
      if (!mounted) return;
      // The person chosen before the question must exist in the shop that
      // answered it. If they do not, say so rather than silently signing in
      // as the owner with somebody else's PIN.
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
      // Till-wide throttle first. Per-user lockout alone can be sidestepped by
      // switching the selected user between attempts, so the whole till has to
      // be able to refuse a sign-in regardless of who is picked.
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
          // Opportunistically re-derive a legacy weak hash on successful
          // sign-in.
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
            // `signInAsStaff` carries the id through, which is what lets
            // analytics scope a cashier to their own sales by `staff_id`
            // instead of by a display name that can be changed and reused.
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

  /// A refused attempt: message published on a live region, digits cleared so
  /// the next attempt starts clean.
  void _refuse(String message) {
    HapticTheme.of(context).fire(HapticEvent.reject);
    setState(() => _error = message);
    _pin.clear();
  }

  /// The way out of a till with no accounts on it. Offered here rather than
  /// left as dead copy, because this screen is reachable without a session and
  /// the pad has nothing to check a PIN against.
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
                  _SignInHeader(shopName: shopName),
                  SizedBox(height: spacing.md),
                  Expanded(
                    child: _choosingShop
                        // The shop chooser, FIRST.
                        //
                        // The roster below belongs to ONE shop. On a phone
                        // with several, the person has to say which one they
                        // are opening — otherwise they are reading one shop's
                        // people and typing one shop's PIN at another shop's
                        // counter, and neither shop is wrong about anything.
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
                  // A way BACK to the chooser, once a shop is open.
                  //
                  // Without it, a person who picked the wrong shop has to
                  // sign out of this one to pick the other — and signing out
                  // to change your mind is a poor trade for a tap.
                  if (!_choosingShop && _shops.length > 1)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => setState(
                          () => _choosingShop = true,
                        ),
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
                  // The PIN, typed into a field with the system's own numeric
                  // keyboard.
                  //
                  // The keypad this replaced took half the screen of a phone
                  // that also has to show the roster, and it could not be
                  // filled by a barcode scanner or a keyboard case. The
                  // system's keyboard is faster, is already the right shape for
                  // a number, and comes with the owner's own input method.
                  // The label follows the field, through the controller — so it
                  // updates on every keystroke without rebuilding the screen
                  // around it. A setState here would redraw the whole login
                  // page for every digit.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _pin,
                    builder: (
                      BuildContext context,
                      TextEditingValue value,
                      Widget? field,
                    ) =>
                        Semantics(
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
                  // The field is disabled while a PIN is being checked, so this
                  // is where that is stated rather than being a dead field.
                  Text(
                    _verifying ? 'Checking this PIN' : '',
                    textAlign: TextAlign.center,
                    style: type.labelSmall?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                  // Forgot PIN lives HERE, on the pad, and nowhere else.
                  //
                  // The only way to reach the settings screen is to unlock the
                  // till, and unlocking the till needs the PIN. Putting recovery
                  // there would put it behind the very thing it recovers — which
                  // is how a shop ends up unable to use its own till with a
                  // staff-less phone in its hand.
                  //
                  // It is shown only when the OWNER is the picked identity and
                  // the owner row actually carries an email. A cashier's PIN is
                  // reset by the owner from Settings, so offering a mailed reset
                  // against a cashier would be a dead button; and a shop that
                  // never verified an email has nothing to send a code to.
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

/// The mark and the shop this till is pointed at.
class _SignInHeader extends StatelessWidget {
  const _SignInHeader({required this.shopName});

  final String shopName;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    // The mark ABOVE the name rather than beside it: the name is the large
    // title on the canvas, and a mark sitting beside it would either fight the
    // title for the first line or push the name down to the app-bar size.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Image(
          image: AssetImage(
            'assets/branding/stitch_simple_pos_launcher_icon/simple_pos_geometric_s_icon/screen.png',
          ),
          width: 36,
          height: 36,
          fit: BoxFit.contain,
        ),
        SizedBox(height: spacing.md),
        ScreenTitle(title: shopName, padding: EdgeInsets.zero),
      ],
    );
  }
}

/// The shops on this phone, and the one to open.
///
/// ## WHY IT IS A SEPARATE SCREEN-FULL OF THINGS
///
/// A till that belongs to one shop has nothing to choose, and a chooser over
/// a single entry is a tap that gets you to where you were going anyway. So
/// this only appears when the phone holds more than one shop.
///
/// ## WHY IT IS BEFORE THE ROSTER
///
/// The roster is a list of PEOPLE, and people belong to a shop. Showing the
/// roster before the shop is chosen means showing the staff of whichever shop
/// happened to be active — and the person would have no way of knowing that
/// the names in front of them are not the names of the shop they are standing
/// in.
class _ShopChooser extends StatelessWidget {
  const _ShopChooser({required this.shops, required this.onChosen});

  /// The shops on this device.
  final List<LocalShop> shops;

  /// What was chosen.
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

/// One shop in the chooser.
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
                    // The name WRAPS: a shop name is typed by a human, and a
                    // name cut off is a name the owner cannot recognise.
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

/// Waiting on the roster. Never a blank frame and never a spinner over content
/// that is already there: nothing is, yet.
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

/// A till with no shop and no staff. Not an error: it is what a device looks
/// like the moment before it is set up, and it is the one state on this screen
/// that has a next action worth offering.
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
                // Decorative: the headline below says the same in words.
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

/// Who is signing in.
///
/// Grouped by role and headed by "Who are you?" rather than a bare dropdown of
/// names, because that dropdown was the whole problem the owner reported: a
/// till with a dozen staff had no way to tell which name was the admin and no
/// way to confirm they had picked themselves before typing a PIN. Grouping puts
/// the three roles where a person expects them.
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

  /// A role's staff, in the order the database returned them.
  Map<ShopRole, List<Staff>> get _byRole {
    final Map<ShopRole, List<Staff>> grouped = <ShopRole, List<Staff>>{};
    for (final Staff member in staff) {
      grouped
          .putIfAbsent(ShopRole.parse(member.role), () => <Staff>[])
          .add(member);
    }
    return grouped;
  }

  /// Stable selection tag for a staff row.
  ///
  /// The same shape the state class builds, restated rather than reached for:
  /// a picker that computed it differently from the selection it is asked about
  /// would show a row as chosen that cannot actually be chosen.
  static String _tagFor(Staff staff) =>
      staff.id == null ? 'name:${staff.name}' : 'staff:${staff.id}';

  bool _sameTag(Staff member) {
    final String tag = _tagFor(member);
    return selected == tag ||
        (selected != null &&
            selected!.startsWith('name:') &&
            selected!.substring(5) == member.name);
  }

  /// The list flattened to headers and people.
  ///
  /// One list, one builder, because a roster is unbounded in principle and
  /// `Column(children: rows)` on a shop with thirty staff is a till that will
  /// not render.
  ///
  /// ONE GROUP PER ROLE, with the owner folded into the admin group rather than
  /// standing as a group of its own. Listing them separately produced two
  /// `admin` groups the moment the shop also had an admin-role staff account,
  /// which rendered the "Admins" header twice and every admin account twice
  /// beneath it — the same person listed as two different accounts, and the
  /// owner listed among them as well.
  /// [l10n] is passed in rather than read from a context, because this is a
  /// [StatelessWidget]: a stateless widget has no `context` of its own outside
  /// `build`, and a heading has to be localised wherever it is built.
  List<_RosterRow> _rows(AppLocalizations l10n) {
    final Map<ShopRole, List<Staff>> byRole = _byRole;
    final List<Staff> chosen = staff.where(_sameTag).toList();
    final bool chosenOwner = selected == '__owner__' && ownerName != null;

    // The roles that actually hold an account, in a fixed order, with the
    // owner folded into the admin group rather than standing as a group of its
    // own. A second group for the same role is what duplicated the "Admins"
    // heading and every account under it.
    //
    // The union, NOT one filtered against the other: excluding admin staff when
    // an owner exists is easy to write and silently drops them from the roster,
    // and excluding the owner when admin staff exist does the same to the only
    // account that can sign in on a new phone.
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
            // The flattened rows are computed ONCE per build. Rebuilding them
            // per item turns a roster of thirty into thirty list rebuilds of
            // the whole roster.
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
        // Echoed below the list, not only inside it. On a busy counter the list
        // scrolls out of view and the selection still has to be confirmable,
        // and a selection that changes with no announcement is a selection a
        // screen-reader user cannot confirm.
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

/// One row of the flattened roster: either a group header or a person.
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

  /// The stable id the callback resolves. Never the name: two staff can share
  /// one, and matching on a display value is how a sale gets attributed to the
  /// wrong person.
  final String? tag;

  final bool selected;

  bool get isHeader => title != null;
}

/// One person on the roster.
///
/// Three channels for "chosen", because a counter till gets looked at by
/// someone who did not choose it: the glyph changes silhouette, the tile fills
/// and takes a heavier edge, and the semantics node carries `selected`.
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
          // The action is declared here and the child is excluded, so this is
          // ONE node. Left unmerged, a screen reader walks into the glyph and
          // the two text runs as three separate stops for one target.
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
                    // Wrapping, never ellipsis: a cashier's name cut in half
                    // is a name they cannot check themselves against.
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

/// How many digits are in, and out loud.
///
/// The dots are a visual echo of a keystroke, so the count is published as a
/// value rather than left to four circles: four shapes is not something anyone

/// The measure of the pad and the roster above it.
///
/// Wider than a phone on purpose: on a tablet the keys get wider, which is the
/// point of a till that might be a 10-inch one on a counter.
const double _kPadWidth = 460;

/// The heading over one role's accounts, localised.
///
/// A plural rather than `'${role.label}s'`: the singular inflected with an `s`
/// is English, and a heading is exactly the kind of string a translated build
/// gets judged on.
String roleSectionTitle(AppLocalizations l10n, ShopRole role) => switch (role) {
      ShopRole.admin => l10n.loginRoleAdmins,
      ShopRole.manager => l10n.loginRoleManagers,
      ShopRole.cashier => l10n.loginRoleCashiers,
    };
