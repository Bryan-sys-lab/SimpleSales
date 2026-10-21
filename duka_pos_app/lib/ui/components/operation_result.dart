// How an operation says what it did.
//
// ## WHY A SHEET AND NOT A SNACKBAR
//
// A snackbar says "done" and vanishes in four seconds. That is enough for a
// tap that changed nothing a person would miss — a filter, a dismiss. It is
// not enough for the operations a shopkeeper waits FOR: an import that took
// two minutes, a backup that made the till's data safe, an update that
// replaced the app.
//
// Those operations end on a SCREEN, with what happened, and one button that
// puts the owner back to work.
//
// ## WHY ONE PLACE
//
// Eleven screens used to report an operation's outcome, and they did it
// eleven ways: some through a snackbar, some through the ERROR helper — so a
// success and a failure looked the same — and several with no failure path
// at all, so a failed import or a failed backup was silent.
//
// One function for the success and one for the failure means the outcome is
// the same everywhere: the same sheet, the same shape, the same "what now".
//
// ## WHY THE FAILURE IS A SHEET AND NOT A TOAST
//
// A failure is the one thing on a till that the owner MUST deal with: the
// import did not run, the backup did not happen, the update did not install.
// A toast that disappears on its own is a failure nobody acts on, and a
// failure nobody acts on is a failure that happens again.

import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../ui/components/states.dart';
import '../../ui/components/success_view.dart';

/// Shows what an operation DID.
///
/// [detail] is the second fact, beside its own marker: how many products, what
/// the file is called, what the reference number was.
Future<void> showOperationSuccess(
  BuildContext context, {
  required String title,
  String? message,
  String? detail,
  IconData detailIcon = Icons.check_circle_outline,
  String? nextLabel,
  VoidCallback? onNext,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Most of the screen: the message is read at arm's length by somebody
    // standing at a counter.
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (BuildContext sheetContext) => SafeArea(
      child: SuccessView(
        title: title,
        message: message ?? '',
        detail: detail,
        detailIcon: detailIcon,
        nextLabel: nextLabel,
        onNext: onNext ?? () => Navigator.pop(sheetContext),
      ),
    ),
  );
}

/// Shows what an operation FAILED to do, and offers the way out.
///
/// [onRetry] is the one thing that can fix it. Null when there is nothing to
/// retry — a malformed file will be malformed again — and then the sheet
/// says so and offers only the way back.
Future<void> showOperationFailure(
  BuildContext context, {
  required String title,
  required String message,
  String? detail,
  IconData icon = Icons.error_outline,
  VoidCallback? onRetry,
  String? retryLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (BuildContext sheetContext) => SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: AppSpacing.of(context).lg,
        ),
        child: ErrorStateView(
          message: message,
          detail: detail,
          icon: icon,
          onRetry: onRetry == null
              ? null
              : () {
                  Navigator.pop(sheetContext);
                  onRetry();
                },
          retryLabel: retryLabel ?? 'Try again',
        ),
      ),
    ),
  );
}

/// Runs [operation] and reports the outcome.
///
/// Returns true when the operation succeeded. The failure sheet is shown for
/// any error the operation throws, so no call site can forget to handle one.
///
/// The error is never shown as an exception's text: an exception is
/// untranslatable, unactionable, and it leaks file paths and ids to whoever
/// is standing at the till. The caller passes the words.
Future<bool> runOperation(
  BuildContext context, {
  required Future<void> Function() operation,
  required String successTitle,
  String? successMessage,
  String? successDetail,
  IconData successIcon = Icons.check_circle_outline,
  String? nextLabel,
  required String failureTitle,
  required String failureMessage,
  String? failureDetail,
  IconData failureIcon = Icons.error_outline,
  VoidCallback? onRetry,
}) async {
  try {
    await operation();
  } on Object {
    if (!context.mounted) return false;
    await showOperationFailure(
      context,
      title: failureTitle,
      message: failureMessage,
      detail: failureDetail,
      icon: failureIcon,
      onRetry: onRetry,
    );
    return false;
  }
  if (!context.mounted) return true;
  await showOperationSuccess(
    context,
    title: successTitle,
    message: successMessage,
    detail: successDetail,
    detailIcon: successIcon,
    nextLabel: nextLabel,
  );
  return true;
}
