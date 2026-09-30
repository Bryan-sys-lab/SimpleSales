import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/app_state.dart';
import '../services/backend_service.dart';
import '../services/workspace_service.dart';

class OwnerSetupScreen extends StatefulWidget {
  const OwnerSetupScreen({super.key});
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
    if (!RegExp(r'^\d{4}$').hasMatch(_pin.text)) {
      setState(() => _error = 'PIN must be exactly 4 digits');
      return;
    }
    if (_pin.text != _pin2.text) {
      setState(() => _error = 'PINs do not match');
      return;
    }
    setState(() => _error = null);
    try {
      final owner = Owner(
        id: 1,
        name: _name.text.trim(),
        pinHash: await AuthService.hashPin(_pin.text),
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
      await context.read<AppState>().loadOwner();
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
                  Text('Set up your shop',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  const Text(
                    'Create the shop admin account. The admin can create managers and cashiers, manage stock, and connect optional services.',
                  ),
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
                    decoration: const InputDecoration(labelText: 'Confirm PIN'),
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    autofillHints: const [AutofillHints.newPassword],
                  ),
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
