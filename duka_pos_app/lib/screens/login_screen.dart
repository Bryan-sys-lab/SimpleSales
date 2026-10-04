import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<Staff> _staff = [];
  String _pin = '';
  String? _error;

  /// The identity currently picked, as a tag string.
  ///
  /// A tag rather than the display name because two staff can legitimately
  /// share a name — "Ali" on the counter and "Ali" doing deliveries — and
  /// matching the selection by name silently signed in the wrong one.
  String? _selected; // '__owner__' or 'staff:<id>'

  @override
  void initState() {
    super.initState();
    _load();
  }

  static const _ownerValue = '__owner__';

  /// Stable selection tag for a staff row.
  ///
  /// Prefers the id, because that is what the ledger keys attribution on.
  /// Falls back to the name only for a row that somehow has no id, which is
  /// then still unique enough to select — though not to attribute a sale to.
  static String _tagFor(Staff staff) =>
      staff.id == null ? 'name:${staff.name}' : 'staff:${staff.id}';

  Staff? get _selectedStaff {
    final tag = _selected;
    if (tag == null || tag == _ownerValue) return null;
    if (tag.startsWith('staff:')) {
      final id = int.tryParse(tag.substring(6));
      if (id == null) return null;
      for (final member in _staff) {
        if (member.id == id) return member;
      }
      return null;
    }
    if (tag.startsWith('name:')) {
      final name = tag.substring(5);
      for (final member in _staff) {
        if (member.name == name) return member;
      }
    }
    return null;
  }

  Future<void> _load() async {
    // Read before the await, never after it: context must not cross an async
    // gap, and the owner cannot change while this screen is being built — the
    // router only reaches the PIN pad once a shop exists.
    final owner = context.read<AppState>().owner;
    final staff = await DatabaseHelper.instance.getStaff();
    if (!mounted) return;
    setState(() {
      _staff = staff;
      // Default to the owner only when there is one. A till whose shop record
      // is missing must still render this screen without dereferencing null.
      _selected = owner != null
          ? _ownerValue
          : (staff.isEmpty ? null : _tagFor(staff.first));
    });
  }

  void _press(String k) {
    setState(() {
      _error = null;
      if (k == '⌫') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 4) {
        _pin += k;
      }
    });
    if (_pin.length == 4) _tryLogin();
  }

  Future<void> _tryLogin() async {
    final state = context.read<AppState>();
    final userKey = _selected ?? '';

    // Till-wide throttle first. Per-user lockout alone can be sidestepped by
    // switching the selected user between attempts, so the whole till has to be
    // able to refuse a sign-in regardless of who is picked.
    if (await AuthService.isTillLockedOut()) {
      final remaining = await AuthService.tillLockoutRemaining();
      if (!mounted) return;
      setState(() {
        _error =
            'Too many wrong PINs on this till. Try again in ${remaining?.inSeconds ?? 0}s.';
        _pin = '';
      });
      return;
    }

    if (await AuthService.isLockedOut(userKey)) {
      final remaining = await AuthService.lockoutRemaining(userKey);
      if (!mounted) return;
      setState(() {
        _error =
            'Too many wrong PINs. Try again in ${remaining?.inSeconds ?? 0}s.';
        _pin = '';
      });
      return;
    }

    bool ok = false;
    final owner = state.owner;
    if (_selected == _ownerValue && owner != null) {
      ok = await AuthService.verifyPin(_pin, owner.pinHash);
      if (!mounted) return;
      if (ok) {
        await AuthService.recordSuccess(userKey);
        // Opportunistically re-derive a legacy weak hash on successful sign-in.
        final hash = owner.pinHash;
        if (AuthService.needsUpgrade(hash)) {
          await DatabaseHelper.instance
              .updateOwnerPin(await AuthService.hashPin(_pin));
        }
        state.signInAsOwner();
        return;
      }
    } else {
      final staff = _selectedStaff;
      if (staff != null) {
        ok = await AuthService.verifyPin(_pin, staff.pinHash);
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
    final lockedNow = await AuthService.isLockedOut(userKey);
    if (!mounted) return;
    setState(() {
      _error = lockedNow
          ? 'Too many wrong PINs. Locked for ${AuthService.lockoutDuration.inSeconds}s.'
          : 'Wrong PIN';
      _pin = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final shopName = state.owner?.shopName ?? 'Duka POS';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(shopName,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  _WhoPicker(
                    ownerName: state.owner?.name,
                    staff: _staff,
                    selected: _selected,
                    onChanged: (v) => setState(() {
                      _selected = v;
                      _pin = '';
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                        4,
                        (i) => Container(
                              margin: const EdgeInsets.all(6),
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    width: 2),
                                color: i < _pin.length
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            )),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      '1',
                      '2',
                      '3',
                      '4',
                      '5',
                      '6',
                      '7',
                      '8',
                      '9',
                      '⌫',
                      '0',
                      ''
                    ]
                        .map((k) => k.isEmpty
                            ? const SizedBox()
                            : OutlinedButton(
                                onPressed: () => _press(k),
                                child: Text(k,
                                    style: const TextStyle(fontSize: 20)),
                              ))
                        .toList(),
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

/// Who is signing in.
///
/// Grouped by role and headed by "Who are you?" rather than a bare dropdown of
/// names, because that dropdown was the whole problem the owner reported: a
/// till with a dozen staff had no way to tell which name was the admin and no
/// way to confirm they had picked themselves before typing a PIN. Grouping puts
/// the three roles where a person expects them, and the selected identity is
/// echoed above the keypad so a mis-pick is visible *before* four digits are
/// committed.
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

  @override
  Widget build(BuildContext context) {
    final byRole = <ShopRole, List<Staff>>{};
    for (final member in staff) {
      byRole.putIfAbsent(ShopRole.parse(member.role), () => []).add(member);
    }

    final groups = <({ShopRole role, String? ownerTag, String title})>[
      if (ownerName != null)
        (role: ShopRole.admin, ownerTag: '__owner__', title: 'Admins'),
      for (final entry in byRole.entries)
        (role: entry.key, ownerTag: null, title: '${entry.key.label}s'),
    ];

    final chosenStaff = staff.where((member) => _sameTag(member)).toList();
    final chosenOwner = selected == '__owner__' && ownerName != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Who are you?', style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 10),
        if (staff.isEmpty && ownerName == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'This shop has no accounts yet. Go back and set it up.',
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final group in groups) ...[
            if (groups.length > 1 || byRole.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Text(
                  group.title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    color: DukaColors.mutedInk,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (group.ownerTag != null)
              _WhoTile(
                name: ownerName!,
                roleLabel: 'Admin',
                selected: chosenOwner,
                onTap: () => onChanged('__owner__'),
              ),
            ...(byRole[group.role] ?? const <Staff>[])
                .where((member) => group.ownerTag == null || member.id != null)
                .map((member) => _WhoTile(
                      name: member.name,
                      roleLabel: ShopRole.parse(member.role).label,
                      selected: chosenStaff.contains(member),
                      onTap: () => onChanged(_tag(member)),
                    )),
          ],
        // Echoed above the keypad, not only in the list. On a busy counter the
        // list scrolls out of view and the selection has to remain confirmable.
        if (selected != null && (chosenOwner || chosenStaff.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Signing in as ${chosenOwner ? ownerName : chosenStaff.first.name}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }

  bool _sameTag(Staff member) {
    final tag = _tag(member);
    return selected == tag ||
        (selected != null &&
            selected!.startsWith('name:') &&
            selected!.substring(5) == member.name);
  }

  static String _tag(Staff member) =>
      member.id == null ? 'name:${member.name}' : 'staff:${member.id}';
}

class _WhoTile extends StatelessWidget {
  const _WhoTile({
    required this.name,
    required this.roleLabel,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String roleLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: selected,
        label: '$name, $roleLabel',
        child: Material(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    size: 20,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : DukaColors.mutedInk,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    roleLabel,
                    style: TextStyle(fontSize: 12, color: DukaColors.mutedInk),
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
