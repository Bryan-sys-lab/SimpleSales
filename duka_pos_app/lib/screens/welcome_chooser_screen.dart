import 'package:flutter/material.dart';

import '../app_brand.dart';
import '../services/app_stage.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'owner_setup_screen.dart';
import 'splash_screen.dart';

/// The first screen a person sees when there is no signed-in session.
///
/// Two choices, always, for everyone: **sign in** or **set up**. This replaces a
/// flow that branched silently on whether a shop happened to exist, so a
/// cashier handed a brand-new till landed on a form addressed to whoever
/// installs the app — "create shop admin account" — with no sign-in anywhere in
/// sight. Nothing about who is holding the phone should decide whether they are
/// offered a way to sign in.
///
/// The shop name is shown so somebody signing in knows *which* shop this device
/// is pointed at before they type a PIN. A shop name is not sensitive — it is
/// printed on every receipt this till issues — and without it a person holding a
/// till set up for someone else has no way to tell they are in the wrong place.
class WelcomeChooserScreen extends StatefulWidget {
  const WelcomeChooserScreen({
    super.key,
    required this.shopName,
    required this.hasShop,
    this.intent = AppChooserIntent.signIn,
  });

  /// The active shop's name, or empty when there is no shop yet.
  final String shopName;

  final bool hasShop;

  /// Where this chooser was entered from. `addShop` changes the setup call's
  /// copy, because adding a second shop is not the same job as creating the
  /// first one.
  final AppChooserIntent intent;

  @override
  State<WelcomeChooserScreen> createState() => _WelcomeChooserScreenState();
}

class _WelcomeChooserScreenState extends State<WelcomeChooserScreen> {
  Future<void> _openLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LoginScreen(),
        fullscreenDialog: true,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openSetup() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OwnerSetupScreen(
          // Adding a second shop must not read as "create the owner for this
          // shop" — the owner already exists elsewhere on this device. The
          // screen uses this to change its own heading and its submit label.
          isAdditionalShop: widget.intent == AppChooserIntent.addShop,
          onCancel: () => Navigator.of(context).pop(false),
        ),
      ),
    );
    if (created == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final addingAnother = widget.intent == AppChooserIntent.addShop;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: SimplePosMark(size: 72)),
                  const SizedBox(height: 18),
                  Semantics(
                    header: true,
                    child: Text(
                      SimplePosBrand.appName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.hasShop && widget.shopName.trim().isNotEmpty)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        addingAnother
                            ? 'Adding another shop. You are signed out of $SimplePosBrand.appName on this device until you sign in.'
                            : 'Signed-in shop: ${widget.shopName}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  else
                    Text(
                      'Choose how you want to start',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 28),

                  // Sign in first, and unconditionally. It is the choice a
                  // returning user makes every single day, and it must never
                  // be the one that is hidden.
                  FilledButton.icon(
                    onPressed: _openLogin,
                    icon: const Icon(Icons.pin_outlined),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(widget.hasShop ? 'Sign in' : 'Sign in'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  OutlinedButton.icon(
                    onPressed: _openSetup,
                    icon: Icon(addingAnother
                        ? Icons.add_business_outlined
                        : Icons.storefront_outlined),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(addingAnother
                          ? 'Set up another shop'
                          : 'Set up a shop on this device'),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    widget.hasShop
                        ? 'Cashiers, managers and admins all sign in with the PIN their shop gave them.'
                        : 'A shop admin sets this device up once. After that, everyone signs in with the PIN they are given. No internet is needed.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    SimplePosBrand.poweredByTag,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: DukaColors.mutedInk,
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