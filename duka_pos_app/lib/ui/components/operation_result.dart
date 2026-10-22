// How an operation says what it did.
//
// ## WHY A POPUP AND NOT A SCREEN
//
// An operation that ends on a screen makes the owner dismiss it before they
// can do anything else. A shopkeeper taps "Save", reads a full page that
// says "Saved", and taps "Next" to get back to what they were doing — three
// taps and two seconds of a counter standing still for a change that was
// already made.
//
// So the outcome is a POPUP: it says what happened over the top of the work
// and it goes away by itself. The owner never has to dismiss anything to
// keep selling.
//
// The one thing a popup must not be is a way of showing something the owner
// has to READ. The exceptions are handled by the screens that show them, not
// here — a backup, an import and an app update still say what they did in
// full, because those are the operations a person waits for and the ones
// where "saved" is not the whole story.
//
// ## WHY ONE PLACE
//
// Eleven screens used to report an operation's outcome, and they did it
// eleven ways: some through a snackbar, some through the ERROR helper — so a
// success and a failure looked the same — and several with no failure path at
// all, so a failed import or a failed backup was silent.
//
// One function for the success and one for the failure means the outcome is
// the same everywhere: the same popup, the same shape, the same "what now".
//
// ## WHY THE FAILURE STAYS LONGER
//
// A success is a fact about the past: the tap landed, the work is done, and
// the popup can go.
//
// A failure is a fact about the future: something did not happen and may need
// doing again. So a failure popup stays up for longer, carries a "Try again"
// when there is something to try, and is announced to a screen reader rather
// than only drawn.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../../ui/components/controls.dart';

/// Shows what an operation DID.
///
/// [detail] is the second fact, beside the first: how many products, what the
/// file is called, what the reference number was.
void showOperationSuccess(
  BuildContext context, {
  required String title,
  String? message,
  String? detail,
  IconData detailIcon = Icons.check_circle_outline,
  String? nextLabel,
  VoidCallback? onNext,
}) {
  if (!context.mounted) return;
  final String text = <String?>[title, message, detail]
      .where((String? part) => part != null && part.trim().isNotEmpty)
      .join(' · ');
  showAppSnackBar(
    context,
    message: text,
    actionLabel: nextLabel,
    onAction: onNext,
  );
}

/// Shows what an operation FAILED to do, and offers the way out.
///
/// [onRetry] is the one thing that can fix it. Null when there is nothing to
/// retry — a malformed file will be malformed again — and then the popup
/// says so and offers nothing to press.
void showOperationFailure(
  BuildContext context, {
  required String title,
  required String message,
  String? detail,
  IconData icon = Icons.error_outline,
  VoidCallback? onRetry,
  String? retryLabel,
}) {
  if (!context.mounted) return;
  final AppColors colors = AppColors.of(context);
  final AppMotion motion = AppMotion.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final bool slow = MediaQuery.accessibleNavigationOf(context);

  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      // A failure is RED, and it says so in words too: the colour is never
      // the only channel. Colour-blindness is not the reason; a red bar at
      // the bottom of a bright till screen is easy to miss, and a person who
      // missed it never learns the import failed.
      backgroundColor: colors.danger,
      content: Text(
        <String?>[title, message, detail]
            .where((String? part) => part != null && part.trim().isNotEmpty)
            .join(' · '),
        style: TextStyle(color: colors.onDangerContainer),
      ),
      // Longer than a success: a failure is the one thing on a till that the
      // owner may have to deal with.
      duration: slow
          ? motion.feedbackExtended
          : (onRetry == null ? motion.feedbackExtended : motion.feedbackBrief),
      action: (onRetry == null)
          ? null
          : SnackBarAction(
              label: retryLabel ?? 'Try again',
              onPressed: onRetry,
            ),
    ),
  );
}

/// Runs [operation] and reports the outcome.
///
/// Returns true when the operation succeeded. The failure popup is shown for
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
    showOperationFailure(
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
  showOperationSuccess(
    context,
    title: successTitle,
    message: successMessage,
    detail: successDetail,
    detailIcon: successIcon,
    nextLabel: nextLabel,
  );
  return true;
}

/// The space a popup needs above the bottom of the screen.
///
/// Used by the screens that keep a full-height sheet, so the popup is not
/// hidden behind it.
double operationPopupInset(BuildContext context) => AppSpacing.of(context).lg;
