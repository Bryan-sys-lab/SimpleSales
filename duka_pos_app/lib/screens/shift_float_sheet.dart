// Asking for one cash amount.
//
// A sheet rather than an `AlertDialog`, for one reason that is not taste: this is
// a numeric keypad entry and a dialog sits in the middle of the screen, so on a
// 640dp-tall till the field ends up under the keyboard. A bottom sheet with
// `viewInsetsOf` applied sits above the keyboard by construction.
//
// The controller is owned by the WIDGET rather than created in the caller and
// disposed the moment the future resolves, which is the bug this file's shape
// exists to prevent: disposing a controller while its route is still animating
// out throws "used after being disposed" on the way out of the sheet, on some
// devices and not others, which is the worst failure mode there is.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';

import '../theme/app_haptics.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../utils/money.dart';
import '../utils/text_input.dart';

/// Asks for a cash amount, returning it, or null if the cashier backed out.
///
/// `null` here is unambiguous: this sheet has no side effect, so dismissing it
/// and cancelling it mean the same thing and both mean "no amount was given".
Future<Money?> showFloatSheet(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialText = '',
}) {
  return showModalBottomSheet<Money>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext context) => _FloatSheet(
      title: title,
      confirmLabel: confirmLabel,
      initialText: initialText,
    ),
  );
}

/// Parses what a cashier typed into an amount, or null when it is not one.
///
/// Rejects a negative amount HERE rather than on save, because a negative float
/// is not a state a shift can be in, and the message is clearer beside the field
/// where the number was typed than in a banner three rows away.
Money? parseAmount(String raw) {
  final double? parsed = parseUserNumber(raw);
  if (parsed == null || !Money.isValidMajor(parsed)) return null;
  return Money.fromMajor(parsed);
}

class _FloatSheet extends StatefulWidget {
  const _FloatSheet({
    required this.title,
    required this.confirmLabel,
    required this.initialText,
  });

  final String title;
  final String confirmLabel;
  final String initialText;

  @override
  State<_FloatSheet> createState() => _FloatSheetState();
}

class _FloatSheetState extends State<_FloatSheet> {
  late final TextEditingController _amount =
      TextEditingController(text: widget.initialText);

  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Commits the field, or explains why it will not.
  ///
  /// The haptic fires on the refusal as well as the acceptance, so a cashier who
  /// taps with an empty field gets the same acknowledgement as one whose figure
  /// landed — otherwise a rejected tap is completely silent and reads as a
  /// dropped button.
  void _submit() {
    final Money? parsed = parseAmount(_amount.text);
    final HapticTheme haptics = HapticTheme.of(context);

    if (parsed == null) {
      haptics.fire(HapticEvent.reject);
      setState(() => _error = AppLocalizations.of(context).shiftFloatInvalid);
      return;
    }

    haptics.fire(HapticEvent.commit);
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);

    return Padding(
      // `viewInsetsOf`, not `MediaQuery.of(context).viewInsets`: the aspect
      // getter rebuilds only when the keyboard appears or hides, where `.of`
      // subscribes this whole sheet to every MediaQuery change — text scale,
      // rotation, contrast.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.md,
                spacing.md,
                spacing.md,
                0,
              ),
              child: Text(
                widget.title,
                style: AppTypography.of(context).titleLarge,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(spacing.md),
              child: TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  // Blocks the characters rather than accepting them and
                  // rejecting them on save: a cashier who cannot type a letter
                  // into a money field does not need to be told they cannot.
                  FilteringTextInputFormatter.allow(userNumberPattern),
                ],
                textInputAction: TextInputAction.done,
                style: AppTypography.money(context, size: 24),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).shiftFloatAmountLabel,
                  errorText: _error,
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
              ),
            ),
            ActionBar(
              secondary: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(AppLocalizations.of(context).actionCancel),
              ),
              primary: FilledButton(
                onPressed: _submit,
                child: Text(widget.confirmLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
