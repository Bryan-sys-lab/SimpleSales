import 'package:flutter/material.dart';
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
import '../ui/components/status.dart';
import '../ui/components/surface.dart';

/// The PIN pad. The only way into the shop.
///
/// This is the highest-consequence screen in the app: every sale, every
/// report, and every price edit in the session is behind four digits and the
/// identity they are checked against. So the pad is built for the two people
/// most likely to be using it badly rather than for the one person who will use
/// it perfectly:
///
///  * **A key is a key.** 44px minimum, a real `InkWell` with a real focus
///    node, and a semantics node that says what it is ("Digit 4"), not what it
///    looks like. Nothing here is a gesture-only target.
///  * **The identity is confirmable before the digits.** The roster is above the
///    pad and the selection is echoed under it, on a live region, so a mis-pick
///    is visible *and* announced before four digits are committed.
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

  /// The PIN length the shop's hashes are built for. A fifth digit cannot be
  /// entered, which is why the pad submits rather than waiting for an OK.
  static const int _pinLength = 4;

  List<Staff> _staff = [];

  /// The identity currently picked, as a tag string.
  ///
  /// A tag rather than the display name because two staff can legitimately
  /// share a name, "Ali" on the counter and "Ali" doing deliveries, and matching
  /// the selection by name silently signed in the wrong one.
  String? _selected; // '__owner__' or 'staff:<id>'

  String _pin = '';
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

  Future<void> _load() async {
    // Read before the await, never after it: context must not cross an async
    // gap, and the owner cannot change while this screen is being built, the
    // router only reaches the PIN pad once a shop exists.
    final Owner? owner = context.read<AppState>().owner;
    final List<Staff> staff = await (widget.staffLoader?.call() ??
        DatabaseHelper.instance.getStaff());
    if (!mounted) return;
    setState(() {
      _staff = staff;
      // Default to the owner only when there is one.
      _selected = owner != null
          ? _ownerValue
          : (staff.isEmpty ? null : _tagFor(staff.first));
      _loading = false;
    });
  }

  void _pressDigit(String digit) {
    if (_verifying || _pin.length >= _pinLength) return;
    setState(() {
      _error = null;
      _pin += digit;
    });
    HapticTheme.of(context).fire(HapticEvent.select);
    if (_pin.length == _pinLength) _tryLogin();
  }

  void _deleteDigit() {
    if (_verifying) return;
    setState(() {
      _error = null;
      if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
    });
    HapticTheme.of(context).fire(HapticEvent.select);
  }

  void _selectIdentity(String? tag) {
    setState(() {
      _selected = tag;
      _pin = '';
      _error = null;
    });
    HapticTheme.of(context).fire(HapticEvent.select);
  }

  Future<void> _tryLogin() async {
    // Read before the await, never after it.
    final AppState state = context.read<AppState>();
    final String userKey = _selected ?? '';

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
      if (_selected == _ownerValue && owner != null) {
        ok = await AuthService.verifyPin(_pin, owner.pinHash);
        if (!mounted) return;
        if (ok) {
          await AuthService.recordSuccess(userKey);
          // Opportunistically re-derive a legacy weak hash on successful
          // sign-in.
          final String hash = owner.pinHash;
          if (AuthService.needsUpgrade(hash)) {
            await DatabaseHelper.instance
                .updateOwnerPin(await AuthService.hashPin(_pin));
          }
          state.signInAsOwner();
          return;
        }
      } else {
        final Staff? staff = _selectedStaff;
        if (staff != null) {
          ok = await AuthService.verifyPin(_pin, staff.pinHash);
          if (!ok && staff.id != null) {
            ok = await StaffCredentialCache.verifyCachedPin(staff.id!, _pin);
          }
          if (!mounted) return;
          if (ok) {
            await AuthService.recordSuccess(userKey);
            if (AuthService.needsUpgrade(staff.pinHash) && staff.id != null) {
              await DatabaseHelper.instance
                  .updateStaffPin(staff.id!, await AuthService.hashPin(_pin));
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
    setState(() {
      _error = message;
      _pin = '';
    });
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
                    child: switch (_rosterState) {
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
                  if (_error != null) ...<Widget>[
                    SizedBox(height: spacing.md),
                    PersistentBanner(
                      message: _error!,
                      icon: Icons.lock_outline,
                      tone: StatusTone.danger,
                    ),
                  ],
                  SizedBox(height: spacing.md),
                  _PinDots(filled: _pin.length, length: _pinLength),
                  SizedBox(height: spacing.sm),
                  _PinPad(
                    enabled: !_verifying,
                    onDigit: _pressDigit,
                    onDelete: _deleteDigit,
                  ),
                  SizedBox(height: spacing.xs),
                  // The pad is disabled while a PIN is being checked, so this is
                  // where that is stated rather than being a dead pad.
                  Text(
                    _verifying ? 'Checking this PIN' : '',
                    textAlign: TextAlign.center,
                    style: type.labelSmall?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
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
    final TextTheme type = AppTypography.of(context);

    return Row(
      children: <Widget>[
        const Image(
          image: AssetImage(
            'assets/branding/stitch_simple_pos_launcher_icon/simple_pos_geometric_s_icon/screen.png',
          ),
          width: 36,
          height: 36,
          fit: BoxFit.contain,
        ),
        SizedBox(width: spacing.md),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(shopName, style: type.headlineSmall),
          ),
        ),
      ],
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
                child: const Text('Set this shop up on the device'),
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
  List<_RosterRow> _rows() {
    final Map<ShopRole, List<Staff>> byRole = _byRole;
    final List<Staff> chosen = staff.where(_sameTag).toList();
    final bool chosenOwner = selected == '__owner__' && ownerName != null;
    final List<({ShopRole role, String title})> groups =
        <({ShopRole role, String title})>[
      if (ownerName != null) (role: ShopRole.admin, title: 'Admins'),
      for (final MapEntry<ShopRole, List<Staff>> entry in byRole.entries)
        (role: entry.key, title: '${entry.key.label}s'),
    ];

    final List<_RosterRow> rows = <_RosterRow>[];
    for (final ({ShopRole role, String title}) group in groups) {
      if (groups.length > 1) rows.add(_RosterRow.header(group.title));
      if (group.role == ShopRole.admin && ownerName != null) {
        rows.add(
          _RosterRow.person(
            name: ownerName!,
            roleLabel: ShopRole.admin.label,
            tag: '__owner__',
            selected: chosenOwner,
          ),
        );
      }
      for (final Staff member in byRole[group.role] ?? const <Staff>[]) {
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
          child: Text('Who are you?', style: type.titleMedium),
        ),
        SizedBox(height: spacing.sm),
        Expanded(
          child: Builder(
            // The flattened rows are computed ONCE per build. Rebuilding them
            // per item turns a roster of thirty into thirty list rebuilds of
            // the whole roster.
            builder: (BuildContext context) {
              final List<_RosterRow> rows = _rows();
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
/// can read at arm's length with confidence.
class _PinDots extends StatelessWidget {
  const _PinDots({required this.filled, required this.length});

  final int filled;
  final int length;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return Semantics(
      liveRegion: true,
      label: AppLocalizations.of(context)
          .loginFilledPINDigitsEntered(filled, length),
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (int index = 0; index < length; index++)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.sm),
                child: Container(
                  width: spacing.xl,
                  height: spacing.xl,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < filled ? colors.accent : Colors.transparent,
                    border: Border.all(
                      color:
                          index < filled ? colors.accent : colors.outlineStrong,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The twelve keys, three across, laid out as rows rather than a grid.
///
/// A grid needs a fixed cell extent to know how tall it is, and a fixed extent
/// on the one control that has to survive a 200% text scale is how digits get
/// clipped. Rows of `Expanded` keys grow with the label instead.
class _PinPad extends StatelessWidget {
  const _PinPad({
    required this.enabled,
    required this.onDigit,
    required this.onDelete,
  });

  /// False while a PIN is being checked, so the pad cannot queue a second
  /// verification behind the first.
  final bool enabled;

  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;

  /// Row-major. `null` is the empty fourth key of the last row: the pad is ten
  /// digits plus delete, and a gap where a key is missing reads as a key that
  /// failed to load.
  static const List<List<String?>> _layout = <List<String?>>[
    <String?>['1', '2', '3'],
    <String?>['4', '5', '6'],
    <String?>['7', '8', '9'],
    <String?>[null, '0', 'del'],
  ];

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Column(
      children: <Widget>[
        for (final List<String?> row in _layout)
          Padding(
            padding: EdgeInsets.only(bottom: spacing.sm),
            child: Row(
              children: <Widget>[
                for (int index = 0; index < row.length; index++)
                  Expanded(
                    child: Padding(
                      // The gap goes BETWEEN keys, not after the last one, so
                      // the pad stays square inside its column.
                      padding: index == row.length - 1
                          ? EdgeInsets.zero
                          : EdgeInsetsDirectional.only(end: spacing.sm),
                      child: switch (row[index]) {
                        null => const SizedBox.shrink(),
                        'del' => _PinKey(
                            semanticLabel: 'Delete the last digit',
                            onPressed: enabled ? onDelete : null,
                            isDelete: true,
                          ),
                        final String digit => _PinKey(
                            // The label is the DISPLAY label plus the thing it
                            // is: "Digit 4", not "4" and not "the fourth key".
                            semanticLabel:
                                AppLocalizations.of(context).loginDigit(digit),
                            onPressed: enabled ? () => onDigit(digit) : null,
                            digit: digit,
                          ),
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One key.
///
/// The semantics node carries the label, the role, and the action, and the
/// visual child is excluded. That is deliberate: a node that only has a label
/// is a node a screen reader reads but cannot activate, and leaving the button's
/// own semantics in place as well produces two nodes for one key.
class _PinKey extends StatelessWidget {
  const _PinKey({
    required this.semanticLabel,
    required this.onPressed,
    this.digit,
    this.isDelete = false,
  });

  final String semanticLabel;
  final VoidCallback? onPressed;
  final String? digit;
  final bool isDelete;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    final Widget glyph = isDelete
        ? Icon(
            Icons.backspace_outlined,
            size: 22,
            color: colors.onSurfaceVariant,
            // Decorative: the parent node already says what this key does.
            semanticLabel: '',
          )
        : Text(digit!, style: type.headlineSmall);

    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: onPressed != null,
      onTap: onPressed,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: spacing.minTapTarget),
        child: Material(
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: shapes.controlRadius,
            side: BorderSide(color: colors.outlineStrong),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: spacing.md),
                child: glyph,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The measure of the pad and the roster above it.
///
/// Wider than a phone on purpose: on a tablet the keys get wider, which is the
/// point of a till that might be a 10-inch one on a counter.
const double _kPadWidth = 460;
