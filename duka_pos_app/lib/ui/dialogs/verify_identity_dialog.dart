// The two steps of Verify: the PIN, then the code from the email.
//
// WHY THEY ARE WIDGETS AND NOT A CALLBACK CHAIN
// Each step has its own failure modes and its own retry, and a shop owner who
// is told "that code is not right, three attempts left" must be able to type
// again without the flow restarting from the top. So each step owns its field,
// its own submitting state and its own error line, and reports only two
// outcomes: accepted, or cancelled.
//
// WHY THE CALLER RETURNS AN ERROR STRING
// The dialog knows nothing about the network, the backend or the locale. It
// hands the typed value to `onSubmit` and renders whatever comes back: null
// means it was accepted and the sheet closes, a string means it is shown
// beside the field and the sheet stays open. That keeps every message — wrong
// PIN, expired code, no signal — in one place, and keeps this file free of
// anything a translation could get wrong.
//
// WHY A SHEET AND NOT A DIALOG
// Both steps are keyboard entry. A dialog sits in the middle of the screen, so
// on a 640dp-tall till the field ends up under the keyboard and the one thing
// the owner has to type is the one thing they cannot see. A sheet with
// `viewInsets` applied sits above the keyboard by construction — the same
// reason the shift float sheet is a sheet.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_haptics.dart';
import '../../theme/app_shapes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/typography.dart';

/// Step one: the 4-digit admin PIN, which proves the person at the till is the
/// shop admin. Returns the PIN, or null if they backed out.
Future<String?> showVerifyPinSheet(
  BuildContext context, {
  required String email,
  required Future<String?> Function(String pin) onSubmit,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) => VerifyIdentityPinSheet(
      email: email,
      onSubmit: onSubmit,
    ),
  );
}

/// Step two: the 6-digit code from the email, plus the way to ask for another.
/// Returns true when the code was accepted, false if they backed out.
Future<bool> showVerifyCodeSheet(
  BuildContext context, {
  required String maskedEmail,
  required Future<String?> Function(String code) onSubmit,
  required Future<String?> Function() onResend,
}) async {
  final bool? accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) => VerifyIdentityCodeSheet(
      maskedEmail: maskedEmail,
      onSubmit: onSubmit,
      onResend: onResend,
    ),
  );
  // A dismissed sheet is a cancellation, not a failure: the shop can come back
  // to it, and the banner in Settings is still there.
  return accepted ?? false;
}

/// The height a sheet may occupy, so a long sentence cannot push the entry off
/// the bottom of a small phone.
double _sheetMaxHeight(BuildContext context) =>
    MediaQuery.sizeOf(context).height * 0.9;

/// The prompt for the admin PIN.
class VerifyIdentityPinSheet extends StatefulWidget {
  const VerifyIdentityPinSheet({
    super.key,
    required this.email,
    required this.onSubmit,
  });

  final String email;

  /// Null to accept, or the message to show beside the field.
  final Future<String?> Function(String pin) onSubmit;

  @override
  State<VerifyIdentityPinSheet> createState() => _VerifyIdentityPinSheetState();
}

class _VerifyIdentityPinSheetState extends State<VerifyIdentityPinSheet> {
  final TextEditingController _pin = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    // The controller belongs to the widget, not to the caller: disposing it
    // from the outside while the route animates out throws on some devices.
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      HapticTheme.of(context).fire(HapticEvent.reject);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final String? failure = await widget.onSubmit(_pin.text.trim());
    if (!mounted) return;
    if (failure == null) {
      HapticTheme.of(context).fire(HapticEvent.commit);
      Navigator.of(context).pop(_pin.text.trim());
      return;
    }
    HapticTheme.of(context).fire(HapticEvent.reject);
    setState(() {
      _submitting = false;
      _error = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _VerifySheetFrame(
      title: AppLocalizations.of(context).settingsVerifyPinTitle,
      actions: <Widget>[
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context).actionCancel),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? _SheetSpinner()
              : Text(AppLocalizations.of(context).actionContinue),
        ),
      ],
      children: <Widget>[
        Text(
          AppLocalizations.of(context).settingsVerifyPinMessage(widget.email),
          style: AppTypography.of(context).bodyMedium,
        ),
        SizedBox(height: AppSpacing.of(context).md),
        Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: TextFormField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            // PINs are digits and nothing else: a four-digit code with a
            // letter in it is a typo the keyboard should not have offered.
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).settingsVerifyPinLabel,
            ),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            validator: (String? value) {
              final String entered = value?.trim() ?? '';
              if (entered.length != 4) {
                return AppLocalizations.of(context).settingsVerifyPinLabel;
              }
              return null;
            },
          ),
        ),
        if (_error != null) ...<Widget>[
          SizedBox(height: AppSpacing.of(context).md),
          VerifyErrorBanner(message: _error!),
        ],
      ],
    );
  }
}

/// The prompt for the emailed code, with the way to ask for another one.
class VerifyIdentityCodeSheet extends StatefulWidget {
  const VerifyIdentityCodeSheet({
    super.key,
    required this.maskedEmail,
    required this.onSubmit,
    required this.onResend,
  });

  final String maskedEmail;
  final Future<String?> Function(String code) onSubmit;

  /// Returns the message to show in place of the previous error. A fresh code
  /// is sent by the caller, which is the only thing that knows how.
  final Future<String?> Function() onResend;

  @override
  State<VerifyIdentityCodeSheet> createState() =>
      _VerifyIdentityCodeSheetState();
}

class _VerifyIdentityCodeSheetState extends State<VerifyIdentityCodeSheet> {
  final TextEditingController _code = TextEditingController();

  String? _error;
  bool _submitting = false;
  bool _resending = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final String entered = _code.text.trim();
    if (entered.length != 6) {
      HapticTheme.of(context).fire(HapticEvent.reject);
      setState(
          () => _error = AppLocalizations.of(context).settingsVerifyCodeLabel);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final String? failure = await widget.onSubmit(entered);
    if (!mounted) return;
    if (failure == null) {
      HapticTheme.of(context).fire(HapticEvent.commit);
      Navigator.of(context).pop(true);
      return;
    }
    HapticTheme.of(context).fire(HapticEvent.reject);
    setState(() {
      _submitting = false;
      _error = failure;
    });
  }

  Future<void> _resend() async {
    if (_resending || _submitting) return;
    setState(() => _resending = true);
    final String? message = await widget.onResend();
    if (!mounted) return;
    setState(() {
      _resending = false;
      // A successful resend reports the new code's address, which doubles as
      // the confirmation the owner is waiting for.
      _error = message;
    });
    HapticTheme.of(context)
        .fire(message == null ? HapticEvent.commit : HapticEvent.reject);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _VerifySheetFrame(
      title: l10n.settingsVerifyCodeTitle,
      actions: <Widget>[
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text(AppLocalizations.of(context).actionCancel),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? _SheetSpinner()
              : Text(AppLocalizations.of(context).actionContinue),
        ),
      ],
      children: <Widget>[
        Text(
          l10n.settingsVerifyCodeMessage(widget.maskedEmail, _expiryMinutes),
          style: AppTypography.of(context).bodyMedium,
        ),
        SizedBox(height: AppSpacing.of(context).md),
        if (_error != null) ...<Widget>[
          VerifyErrorBanner(message: _error!),
          SizedBox(height: AppSpacing.of(context).md),
        ],
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          // The platform's own SMS autofill: the code arrives in a
          // notification, and typing six digits off a lock screen is the one
          // step in this flow that loses people.
          autofillHints: const <String>[AutofillHints.oneTimeCode],
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(labelText: l10n.settingsVerifyCodeLabel),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        SizedBox(height: AppSpacing.of(context).sm),
        // Always available, never the primary action: the owner who did not
        // get the email should not have to cancel and start again.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: _resending || _submitting ? null : _resend,
            child: Text(l10n.settingsVerifyResendAction),
          ),
        ),
      ],
    );
  }

  /// How long the code is good for, in the units the message wants. The server
  /// is the authority on the number; this is the copy's rounding of it.
  static const int _expiryMinutes = 10;
}

/// The sheet both steps share: title, whatever the step needs, and the actions
/// pinned below the keyboard.
///
/// The body scrolls so a long sentence at 2.0x text never costs the owner the
/// entry field, and the actions sit outside the scroll so Cancel is always
/// reachable — a sheet whose only exit requires a scroll gesture is a trap at
/// the largest text scale.
class _VerifySheetFrame extends StatelessWidget {
  const _VerifySheetFrame({
    required this.title,
    required this.children,
    required this.actions,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: _sheetMaxHeight(context)),
      // A Material of its own. The modal sheet route supplies one around the
      // builder's result, but this widget is also pumped on its own in tests
      // and previewed without a route, and "No Material widget found" from a
      // TextField is not an error anyone should have to diagnose twice.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          // `viewInsetsOf`, not `.of`: the aspect getter rebuilds only when the
          // keyboard appears, where `.of` subscribes the whole sheet to every
          // MediaQuery change.
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.lg,
                end: spacing.lg,
                top: spacing.lg,
                bottom: spacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    title,
                    textAlign: TextAlign.start,
                    style: AppTypography.of(context).titleLarge,
                  ),
                  SizedBox(height: spacing.md),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      ),
                    ),
                  ),
                  SizedBox(height: spacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
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

class _SheetSpinner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 16,
      width: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

/// The failure line, shared so both steps say "this did not work" the same
/// way — which is the whole point of a sheet that stays open.
class VerifyErrorBanner extends StatelessWidget {
  const VerifyErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    return Container(
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colors.dangerContainer,
        borderRadius: AppShapes.of(context).controlRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: colors.onDangerContainer),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.of(context)
                  .bodySmall
                  ?.copyWith(color: colors.onDangerContainer),
            ),
          ),
        ],
      ),
    );
  }
}
