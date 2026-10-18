// Forgot PIN: a code from the email, then a new owner PIN.
//
// WHY IT IS ONE DIALOG AND NOT TWO SHEETS
// The two steps belong to one decision — "I want a new PIN" — and the second
// one is worthless without the first. Splitting them across two sheets would
// make the owner hold a half-finished reset while they go and read their
// email, and the app would still be showing "enter your new PIN" over a
// keyboard that has gone away.
//
// WHY THE NEW PIN IS TYPED TWICE
// A mistyped PIN installed silently is a PIN the owner does not know, and they
// will find out the next time they try to unlock the till. The confirmation
// field costs one keystroke and removes an entire class of "I am locked out of
// my own shop".

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/app_state.dart';
import '../../services/backend_service.dart';
import '../../services/pin_reset_service.dart';
import '../../theme/app_spacing.dart';
import 'package:provider/provider.dart';

/// What the reset produced, returned to the screen that opened it.
class PinResetResult {
  const PinResetResult.completed() : completed = true;
  const PinResetResult.cancelled() : completed = false;

  final bool completed;
}

/// The dialog itself. Takes no database, no backend and no session: the
/// [PinResetService] owns those, and a dialog that reaches them would be a
/// dialog that cannot be tested.
///
/// [ownerEmail] is the address on the account, shown masked. The dialog does
/// not send anything until the owner asks it to.
class PinResetDialog extends StatefulWidget {
  const PinResetDialog({required this.ownerEmail, super.key});

  final String ownerEmail;

  @override
  State<PinResetDialog> createState() => PinResetDialogState();
}

class PinResetDialogState extends State<PinResetDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _pinAgain = TextEditingController();

  /// Which of the two steps is showing.
  ///
  /// The request step is not a separate screen: it is a button and a line of
  /// text, and it disappears once a code has been asked for.
  bool _codeRequested = false;

  bool _requesting = false;
  bool _confirming = false;
  String? _error;

  /// The address the code went to, masked, for the line that says where to
  /// look. Held apart from [AppLocalizations] so the second render of this
  /// state does not re-request a code.
  String? _maskedEmail;

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    _pinAgain.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    setState(() {
      _requesting = true;
      _error = null;
    });
    try {
      final outcome = await PinResetService.requestCode();
      if (!mounted) return;
      setState(() {
        _maskedEmail = outcome.maskedEmail;
        _codeRequested = true;
        _requesting = false;
      });
    } on PinResetException catch (e) {
      if (!mounted) return;
      setState(() {
        _requesting = false;
        _error = _messageFor(e);
      });
    }
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    if (_pin.text.trim() != _pinAgain.text.trim()) {
      setState(() => _error = l10n.pinResetPinsDiffer);
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(_pin.text.trim())) {
      setState(() => _error = l10n.pinResetPinShape);
      return;
    }
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final done = await PinResetService.confirm(
        code: _code.text.trim(),
        newPin: _pin.text.trim(),
        state: _stateForAudit,
      );
      if (!mounted) return;
      if (done) {
        Navigator.of(context).pop(const PinResetResult.completed());
      } else {
        setState(() {
          _confirming = false;
          _error = l10n.pinResetCodeWrong;
        });
      }
    } on PinResetException catch (e) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _error = _messageFor(e);
      });
    }
  }

  /// The session the audit row is attributed by.
  ///
  /// Read from the InheritedWidget rather than passed in, because this dialog
  /// is opened by the settings screen, which already has it in scope — and a
  /// reset that changed the owner's credential is exactly the action an audit
  /// log exists to record.
  AppState get _stateForAudit => Provider.of<AppState>(context, listen: false);

  String _messageFor(PinResetException e) {
    final l10n = AppLocalizations.of(context);
    return switch (e.failure) {
      PinResetFailure.offline => l10n.pinResetOffline,
      PinResetFailure.timeout => l10n.pinResetTimeout,
      PinResetFailure.tooManyAttempts => l10n.pinResetTooMany,
      PinResetFailure.codeRejected => l10n.pinResetCodeWrong,
      PinResetFailure.emailUnknown => l10n.pinResetNoEmail,
      PinResetFailure.challengeMissing => l10n.pinResetStartOver,
      PinResetFailure.server => l10n.pinResetServer,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spacing = AppSpacing.of(context);

    return PopScope(
      // System back is the other way out of a dialog with
      // `barrierDismissible: false`, so it drops the challenge as Cancel does.
      // Without this, a shop dismissed by a back press leaves a redeemable code
      // in the database — the exact state `forgetChallenge` exists to prevent.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (didPop) return;
        // Read the navigator BEFORE the await, then use the reference after it.
        // The guard this exists for is a context used across an async gap, and
        // a `State.context` read after one is exactly that — so the read is
        // hoisted, and only the `pop` happens on the other side.
        final NavigatorState nav = Navigator.of(context);
        await PinResetService.forgetChallenge();
        if (!mounted) return;
        nav.pop(const PinResetResult.cancelled());
      },
      child: AlertDialog(
        title: Text(l10n.pinResetTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (!_codeRequested) ...<Widget>[
                Text(l10n.pinResetIntro(_maskedOrOwnerEmail())),
                SizedBox(height: spacing.md),
                FilledButton(
                  onPressed: _requesting ? null : _requestCode,
                  child: Text(_requesting
                      ? l10n.pinResetSending
                      : l10n.pinResetSendCode),
                ),
              ] else ...<Widget>[
                Text(
                  _maskedEmail == null
                      ? l10n.pinResetSentTo(_maskedOrOwnerEmail())
                      : l10n.pinResetSentTo(_maskedEmail!),
                ),
                SizedBox(height: spacing.md),
                // The mailed code. Digits only, because a code with a stray
                // character in it is one the owner will retype from a screen they
                // can barely see on the phone in their other hand.
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.pinResetCodeLabel,
                    hintText: '000000',
                  ),
                ),
                SizedBox(height: spacing.md),
                TextField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration:
                      InputDecoration(labelText: l10n.pinResetNewPinLabel),
                ),
                SizedBox(height: spacing.sm),
                TextField(
                  controller: _pinAgain,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration:
                      InputDecoration(labelText: l10n.pinResetNewPinAgainLabel),
                  onSubmitted: (_) => _confirming ? null : _confirm(),
                ),
              ],
              if (_error != null) ...<Widget>[
                SizedBox(height: spacing.sm),
                Text(
                  _error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            // The challenge is dropped BEFORE the dialog goes away.
            //
            // `requestCode` persists the challenge id to this shop's database, and
            // leaving it there after a cancelled reset is exactly the situation the
            // design says it prevents: the next person at the counter can finish
            // the reset with the emailed code. `forgetChallenge` is also called on
            // success, so this is the other half of the same contract — and it
            // used to be the missing one.
            onPressed: () async {
              // Navigator read before the await; see the note in `build`.
              final NavigatorState nav = Navigator.of(context);
              await PinResetService.forgetChallenge();
              if (!mounted) return;
              nav.pop(const PinResetResult.cancelled());
            },
            child: Text(l10n.actionCancel),
          ),
          if (_codeRequested)
            FilledButton(
              onPressed: _confirming ? null : _confirm,
              child: Text(_confirming ? l10n.pinResetSaving : l10n.actionSave),
            ),
        ],
      ),
    );
  }

  /// What to show before the server has told us where the code went.
  ///
  /// The address itself is the only honest placeholder, and it is masked the
  /// same way the server's answer will be, so the line does not change shape
  /// between the two renders.
  String _maskedOrOwnerEmail() => PinResetService.maskEmail(widget.ownerEmail);
}
