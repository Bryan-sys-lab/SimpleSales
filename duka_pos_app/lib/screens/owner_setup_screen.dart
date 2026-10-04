import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/app_state.dart';
import '../services/backend_service.dart';
import '../services/workspace_service.dart';

class OwnerSetupScreen extends StatefulWidget {
  /// Shown as a back affordance when this screen was entered from another one.
  /// Null when it is the app's only entry point and there is nowhere to go back
  /// to.
  final VoidCallback? onCancel;

  /// True when this device already runs a shop and this is a *second* one.
  ///
  /// Changes the copy and, more importantly, the defaults: the new shop's admin
  /// is pre-filled from the existing owner and keeps the same PIN, because it
  /// is the same person. Asking a shop owner to invent a new PIN and a new email
  /// for the branch they work in every day is what made "add another shop"
  /// feel like registering from scratch.
  final bool isAdditionalShop;

  /// The owner to carry across. Null when this is the first shop.
  final Owner? carryOverFrom;

  /// Called after a successful create, with the new shop's name.
  final ValueChanged<String>? onCreated;

  const OwnerSetupScreen({
    super.key,
    this.onCancel,
    this.isAdditionalShop = false,
    this.carryOverFrom,
    this.onCreated,
  });
  @override
  State<OwnerSetupScreen> createState() => _OwnerSetupScreenState();
}

class _OwnerSetupScreenState extends State<OwnerSetupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _shop = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  String? _error;

  /// True when the PIN fields are hidden because the existing admin's hash is
  /// being reused.
  ///
  /// The plaintext is never needed and never held: the new owner's row is given
  /// the *existing hash*, so the same four digits the owner already uses keep
  /// working on the new shop. Asking them to retype it would make adding a
  /// branch feel like registering from scratch, which is the thing they were
  /// avoiding.
  bool get _reusingPin =>
      widget.isAdditionalShop && widget.carryOverFrom != null;

  @override
  void initState() {
    super.initState();
    final previous = widget.carryOverFrom;
    if (!widget.isAdditionalShop || previous == null) return;
    // Pre-filled and editable: two admins at the same business may share a
    // device legitimately, and forcing the name they type to match the old
    // owner would be a strange constraint.
    _name.text = previous.name;
    _email.text = previous.email;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _shop.dispose();
    _pin.dispose();
    _pin2.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final email = _email.text.trim().toLowerCase();
    if (_name.text.trim().isEmpty ||
        _shop.text.trim().isEmpty ||
        email.isEmpty) {
      setState(() => _error = 'Enter your name, email, and shop name');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    // The PIN is only asked for when there is nothing to inherit. Re-asking for
    // it on a second shop is what made this flow feel like signing up again.
    if (!_reusingPin) {
      if (!RegExp(r'^\d{4}$').hasMatch(_pin.text)) {
        setState(() => _error = 'PIN must be exactly 4 digits');
        return;
      }
      if (_pin.text != _pin2.text) {
        setState(() => _error = 'PINs do not match');
        return;
      }
    }
    setState(() => _error = null);
    try {
      final owner = Owner(
        id: 1,
        name: _name.text.trim(),
        pinHash: _reusingPin
            ? widget.carryOverFrom!.pinHash
            : await AuthService.hashPin(_pin.text),
        email: email,
        shopName: _shop.text.trim(),
        createdAt: DateTime.now().toIso8601String(),
      );
      await DatabaseHelper.instance.createOwner(owner);
      await WorkspaceService.register(
          workspaceKey: await WorkspaceService.activeWorkspaceKey(),
          shopName: owner.shopName);
      // Online identity/tenant provisioning is opportunistic. The shop still
      // completes setup fully offline; a later owner action can retry it.
      try {
        await BackendService.linkShopToBackend(
            shopName: owner.shopName,
            ownerName: owner.name,
            email: owner.email);
      } catch (_) {
        // Do not turn an offline-first local setup into an online dependency.
      }
      if (!mounted) return;
      // Land the person straight into the new shop. Pushing the shop list and
      // making them choose is what used to happen here, and it dumped them back
      // on a landing page asking to create an admin they had already created.
      await context.read<AppState>().loadOwner();
      if (!mounted) return;
      await context.read<AppState>().signInAsOwner();
      widget.onCreated?.call(owner.shopName);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error =
          "Couldn't save — check the phone has storage space free, then try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.onCancel != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: widget.onCancel,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back'),
                      ),
                    ),
                  Text(
                    widget.isAdditionalShop
                        ? 'Add another shop'
                        : 'Set up your shop',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _reusingPin
                        ? 'This shop reuses the admin account and PIN you '
                            'already use. Give the new shop its own name and '
                            'you will go straight into it.'
                        : 'Create the shop admin account. The admin can create '
                            'managers and cashiers, manage stock, and connect '
                            'optional services.',
                  ),
                  if (_reusingPin) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.lock_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'The PIN already set on this device stays the same '
                            'on this shop. You will not be asked for it again.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  TextField(
                      controller: _shop,
                      decoration: const InputDecoration(labelText: 'Shop name'),
                      autofillHints: const [AutofillHints.organizationName]),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                          labelText: 'Your name (shop admin)'),
                      autofillHints: const [AutofillHints.name]),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'Owner email (Keycloak identity)'),
                      autofillHints: const [AutofillHints.email]),
                  if (!_reusingPin) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pin,
                      decoration:
                          const InputDecoration(labelText: 'Set a 4-digit PIN'),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 4,
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    TextField(
                      controller: _pin2,
                      decoration:
                          const InputDecoration(labelText: 'Confirm PIN'),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 4,
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 8),
                  FilledButton(
                      onPressed: _create,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Create shop admin account'),
                      )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
