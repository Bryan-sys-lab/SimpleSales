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

  Future<void> _load() async {
    final staff = await DatabaseHelper.instance.getStaff();
    if (!mounted) return;
    setState(() {
      _staff = staff;
      _selected = '__owner__';
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

    if (AuthService.isLockedOut(userKey)) {
      final remaining = AuthService.lockoutRemaining(userKey);
      setState(() {
        _error =
            'Too many wrong PINs. Try again in ${remaining?.inSeconds ?? 0}s.';
        _pin = '';
      });
      return;
    }

    bool ok = false;
    if (_selected == '__owner__') {
      ok = await AuthService.verifyPin(_pin, state.owner!.pinHash);
      if (!mounted) return;
      if (ok) {
        AuthService.recordSuccess(userKey);
        state.signIn(state.owner!.name, asOwner: true);
        return;
      }
    } else {
      final match = _staff.where((s) => s.name == _selected);
      if (match.isNotEmpty) {
        ok = await AuthService.verifyPin(_pin, match.first.pinHash);
        if (!mounted) return;
        if (ok) {
          AuthService.recordSuccess(userKey);
          state.signIn(match.first.name,
              asOwner: false, role: match.first.role);
          return;
        }
      }
    }

    AuthService.recordFailure(userKey);
    final lockedNow = AuthService.isLockedOut(userKey);
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
                      DropdownMenuItem(
                          value: '__owner__',
                          child: Text('${state.owner?.name} (Admin)')),
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
