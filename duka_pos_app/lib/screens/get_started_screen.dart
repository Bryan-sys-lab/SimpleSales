import 'package:flutter/material.dart';

import 'owner_setup_screen.dart';

/// First screen on a till that has no shop yet.
///
/// This is till setup, not registration. The wording matters: a shop has one
/// admin, but *every* till needs its own local copy of that shop, so the same
/// admin completes this once per device. Cashiers never do it — the admin adds
/// them in Settings afterwards and they sign in at the PIN pad with their own
/// PIN.
///
/// There is deliberately no "restore from a backup" option here. Encrypted
/// backups are keyed per install (the key lives in this device's keystore and
/// never travels in the file) and the workbook exports carry inventory only,
/// so a file from another till can restore products but never an owner or a
/// staff roster. Offering the button would promise a till provisioning path
/// that does not exist. Restoring data onto a till that already has its owner
/// is a different job and stays on the recovery screen.
class GetStartedScreen extends StatefulWidget {
  const GetStartedScreen({super.key});

  @override
  State<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends State<GetStartedScreen> {
  bool _settingUp = false;

  @override
  Widget build(BuildContext context) {
    if (_settingUp) {
      return OwnerSetupScreen(onCancel: () => setState(() => _settingUp = false));
    }
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
                  Icon(Icons.point_of_sale_outlined,
                      size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 24),
                  Semantics(
                    header: true,
                    child: Text(
                      'Set up this till',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A shop admin sets up each till once. After that, cashiers '
                    'sign in here with the PIN the admin gives them.\n\n'
                    'Setup needs no internet — sales keep working with no '
                    'signal, and you can connect online services later.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: () => setState(() => _settingUp = true),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Create shop admin account'),
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