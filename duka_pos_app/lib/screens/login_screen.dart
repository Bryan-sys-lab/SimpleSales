import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<Staff> _staff = [];
  String? _selected; // staff name, or '__owner__'
  String _pin = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static const _ownerValue = '__owner__';

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
      _selected =
          owner != null ? _ownerValue : (staff.isEmpty ? null : staff.first.name);
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
        state.signIn(owner.name, asOwner: true);
        return;
      }
    } else {
      final match = _staff.where((s) => s.name == _selected);
      if (match.isNotEmpty) {
        final staff = match.first;
        ok = await AuthService.verifyPin(_pin, staff.pinHash);
        if (!mounted) return;
        if (ok) {
          await AuthService.recordSuccess(userKey);
          if (AuthService.needsUpgrade(staff.pinHash) && staff.id != null) {
            await DatabaseHelper.instance
                .updateStaffPin(staff.id!, await AuthService.hashPin(_pin));
          }
          state.signIn(staff.name, asOwner: false, role: staff.role);
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
                  DropdownButtonFormField<String>(
                    initialValue: _selected,
                    items: [
                      if (state.owner != null)
                        DropdownMenuItem(
                            value: _ownerValue,
                            child: Text('${state.owner!.name} (Admin)')),
                      ..._staff.map((s) => DropdownMenuItem(
                          value: s.name, child: Text('${s.name} (${s.role})'))),
                    ],
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
