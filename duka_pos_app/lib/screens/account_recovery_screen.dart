import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/generated/app_localizations.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
import '../services/backend_service.dart';
import '../services/identity_service.dart';
import '../services/pin_reset_service.dart';
import '../services/workspace_service.dart';
import '../ui/dialogs/pin_reset_dialog.dart';

class AccountRecoveryScreen extends StatefulWidget {
  const AccountRecoveryScreen({super.key});

  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  final _email = TextEditingController();
  final _pin = TextEditingController();
  final _passphrase = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pin.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _chooseShop(
    List<Map<String, dynamic>> shops,
  ) {
    if (shops.length == 1) return Future.value(shops.single);
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context).accountRecoveryChooseShop),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: shops
                .map((shop) => ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(shop['shopName'] as String? ?? 'Shop'),
                      subtitle: Text(shop['tenantId'] as String? ?? ''),
                      onTap: () => Navigator.pop(dialogContext, shop),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _recover() async {
    final l10n = AppLocalizations.of(context);
    final email = _email.text.trim().toLowerCase();
    final pin = _pin.text.trim();
    final passphrase = _passphrase.text;
    if (email.isEmpty) {
      setState(() => _error = l10n.accountRecoveryEnterEmail);
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(() => _error = l10n.accountRecoveryInvalidPin);
      return;
    }
    if (passphrase.length < 8) {
      setState(() => _error = l10n.accountRecoveryInvalidPassphrase);
      return;
    }

    final appState = context.read<AppState>();
    String? previousWorkspace;
    String? recoveryWorkspace;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      previousWorkspace = await WorkspaceService.activeWorkspaceKey();
      if (!await IdentityService.login(email, pin)) {
        throw StateError(l10n.accountRecoverySignInFailed);
      }

      final shops = (await BackendService.listMyShops())
          .where((shop) => shop['role'] == 'admin')
          .toList();
      if (shops.isEmpty) throw StateError(l10n.accountRecoveryNoOwnedShop);
      final shop = await _chooseShop(shops);
      if (!mounted) {
        await IdentityService.logout();
        return;
      }
      if (shop == null) {
        await IdentityService.logout();
        return;
      }

      final tenantId = shop['tenantId'] as String?;
      if (tenantId == null || tenantId.isEmpty) {
        throw const FormatException('The account returned an invalid shop ID');
      }
      if (await WorkspaceService.workspaceForTenant(tenantId) != null) {
        throw StateError(l10n.accountRecoveryAlreadyOnDevice);
      }

      recoveryWorkspace = await WorkspaceService.createReadableWorkspaceKey(
        ownerName: email,
        shopName: shop['shopName'] as String? ?? 'Shop',
      );
      await WorkspaceService.register(
        workspaceKey: recoveryWorkspace,
        tenantId: tenantId,
        shopName: shop['shopName'] as String? ?? 'Shop',
      );
      await WorkspaceService.setActiveWorkspace(recoveryWorkspace);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        AppState.identityVerifiedKeyFor(recoveryWorkspace),
        true,
      );

      final restored =
          await BackendService.restorePortableFullBackupFromBackend(passphrase);
      if (!restored) throw StateError(l10n.accountRecoveryNoBackup);

      // The email-authenticated PIN becomes the local owner PIN on the
      // replacement device, so the restored shop can be unlocked immediately.
      await PinResetService.installPin(pin);
      await appState.switchWorkspace(
        recoveryWorkspace,
        signIn: true,
        endOnlineSession: false,
      );
      if (!mounted) return;
      context.go(Routes.dashboard);
    } catch (error, stack) {
      debugPrint('Shop recovery failed: $error\n$stack');
      var cleanupFailed = false;
      if (recoveryWorkspace != null) {
        try {
          await WorkspaceService.unregister(recoveryWorkspace);
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(
            AppState.identityVerifiedKeyFor(recoveryWorkspace),
          );
          final previous = previousWorkspace;
          if (previous == null) {
            throw StateError('Previous workspace was not loaded');
          }
          await WorkspaceService.setActiveWorkspace(previous);
          await appState.switchWorkspace(
            previous,
            signIn: false,
            endOnlineSession: false,
          );
        } catch (cleanupError, cleanupStack) {
          cleanupFailed = true;
          debugPrint(
            'Shop recovery cleanup failed: $cleanupError\n$cleanupStack',
          );
        }
      }
      await IdentityService.logout();
      if (mounted) {
        setState(() => _error = cleanupFailed
            ? l10n.accountRecoveryCleanupFailed
            : error is StateError
                ? error.message.toString()
                : l10n.accountRecoveryFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPin() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() =>
          _error = AppLocalizations.of(context).accountRecoveryEnterEmail);
      return;
    }
    String? challengeId;
    String? resetPin;
    final result = await showDialog<PinResetResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinResetDialog(
        ownerEmail: email,
        requestCode: () async {
          challengeId = await BackendService.requestPinReset(email: email);
          return PinResetOutcome(
            maskedEmail: PinResetService.maskEmail(email),
          );
        },
        confirm: (code, newPin) async {
          final challenge = challengeId;
          if (challenge == null) {
            throw const PinResetException(PinResetFailure.challengeMissing);
          }
          final accepted = await BackendService.confirmPinReset(
            email: email,
            challengeId: challenge,
            code: code,
            newPin: newPin,
          );
          if (accepted) resetPin = newPin;
          return accepted;
        },
      ),
    );
    if (result?.completed == true && resetPin != null && mounted) {
      setState(() {
        _pin.text = resetPin!;
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.accountRecoveryTitle),
        leading: IconButton(
          onPressed: _busy ? null : () => context.go(Routes.login),
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.accountRecoveryDescription,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textCapitalization: TextCapitalization.none,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          labelText: l10n.accountRecoveryEmail,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pin,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(
                          labelText: l10n.accountRecoveryPin,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: _busy ? null : _forgotPin,
                          child: Text(l10n.accountRecoveryForgotPin),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passphrase,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: l10n.accountRecoveryPassphrase,
                          helperText: l10n.accountRecoveryPassphraseHelp,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy ? null : _recover,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.restore),
                        label: Text(_busy
                            ? l10n.accountRecoveryWorking
                            : l10n.accountRecoveryAction),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
