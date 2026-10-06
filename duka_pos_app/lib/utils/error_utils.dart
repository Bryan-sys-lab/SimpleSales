import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';

/// A recoverable failure, with a STABLE code.
///
/// The code is what gets matched and what a message is keyed off. It is not a
/// localized string: a failure carries a code, the view turns it into words. That
/// separation is what makes adding Swahili a translation task instead of a
/// refactor, and it is why a failure can be logged and compared without parsing
/// English.
///
/// [detail] is for the crash reporter and the log. It is never rendered — an
/// exception in the UI is untranslatable, unactionable, and leaks file paths and
/// database ids to whoever is standing at the till.
enum PosFailureCode {
  /// The name being saved is already taken.
  duplicateName,

  /// A required field was left blank.
  missingField,

  /// A write failed for a reason the user can retry.
  writeFailed,

  /// No network.
  offline,

  /// The network is there but did not answer in time.
  timedOut,

  /// The online session expired.
  sessionExpired,

  /// This role may not do that.
  notPermitted,

  /// The payment did not go through.
  paymentFailed,

  /// Not enough stock to complete the sale.
  insufficientStock,

  /// Anything not recognised.
  unknown,
}

/// One failure, thrown as a value and caught as one.
@immutable
class PosFailure implements Exception {
  const PosFailure(this.code, {this.detail});

  final PosFailureCode code;

  /// The cause, for the crash reporter. Never shown to a user.
  final String? detail;

  @override
  String toString() =>
      'PosFailure(${code.name}${detail == null ? '' : ': $detail'})';
}

/// Turns errors into something a shopkeeper can act on.
///
/// The string-matching fallback is retained deliberately. It is ugly, and it is
/// the reason this class exists as a boundary at all: the callers still throw raw
/// exceptions from `DatabaseHelper` and the service layer, so something has to
/// absorb them. What this class buys is that the absorbing happens in ONE place —
/// so replacing a raw throw with a typed [PosFailure] upstream is a change that
/// removes a branch here rather than adding one.
///
/// Prefer throwing [PosFailure] in new code. `userMessage` handles both.
abstract final class ErrorUtils {
  const ErrorUtils._();

  /// The human sentence for a typed failure.
  ///
  /// Switched EXHAUSTIVELY, so adding a code to [PosFailureCode] is a compile
  /// error here rather than a screen that quietly falls through to "Something
  /// went wrong". That exhaustiveness is the whole reason this switch is written
  /// out rather than driven by a lookup table: the sentence is COPY, and copy has
  /// to be translatable, so it lives in the ARB — but the mapping from code to
  /// sentence is logic, and logic is where a compiler can check it.
  static String messageFor(AppLocalizations l10n, PosFailureCode code) =>
      switch (code) {
        PosFailureCode.duplicateName => l10n.errorDuplicateName,
        PosFailureCode.missingField => l10n.errorMissingField,
        PosFailureCode.writeFailed => l10n.errorWriteFailed,
        PosFailureCode.offline => l10n.errorOffline,
        PosFailureCode.timedOut => l10n.errorTimedOut,
        PosFailureCode.sessionExpired => l10n.errorSessionExpired,
        PosFailureCode.notPermitted => l10n.errorNotPermitted,
        PosFailureCode.paymentFailed => l10n.errorPaymentFailed,
        PosFailureCode.insufficientStock => l10n.errorInsufficientStock,
        PosFailureCode.unknown => l10n.errorUnknown,
      };

  /// The human sentence for anything at all.
  static String userMessage(AppLocalizations l10n, Object error) {
    if (error is PosFailure) return messageFor(l10n, error.code);

    final String text = error.toString().toLowerCase();

    if (text.contains('sqlite') || text.contains('database')) {
      if (text.contains('unique constraint')) {
        return messageFor(l10n, PosFailureCode.duplicateName);
      }
      if (text.contains('not null')) {
        return messageFor(l10n, PosFailureCode.missingField);
      }
      return messageFor(l10n, PosFailureCode.writeFailed);
    }

    if (text.contains('socketexception') || text.contains('connection')) {
      return messageFor(l10n, PosFailureCode.offline);
    }
    if (text.contains('timeout')) {
      return messageFor(l10n, PosFailureCode.timedOut);
    }
    if (text.contains('401') || text.contains('unauthorized')) {
      return messageFor(l10n, PosFailureCode.sessionExpired);
    }
    if (text.contains('403') || text.contains('forbidden')) {
      return messageFor(l10n, PosFailureCode.notPermitted);
    }
    if (text.contains('payhero') || text.contains('mpesa')) {
      return messageFor(l10n, PosFailureCode.paymentFailed);
    }
    if (text.contains('stock') || text.contains('inventory')) {
      return messageFor(l10n, PosFailureCode.insufficientStock);
    }
    return messageFor(l10n, PosFailureCode.unknown);
  }

  /// Reports a failure.
  ///
  /// A SNACKBAR, and only ever for a failure the user can see has been handled:
  /// the write rolled back, or nothing was changed. Anything that still matters in
  /// ten seconds belongs in a banner or an inline state, not here — a snackbar
  /// auto-dismisses and a screen reader may never reach it.
  ///
  /// No "OK" action. The old version put an `OK` button on a snackbar that needed
  /// no acknowledgement, which is a control that does nothing.
  static void showError(BuildContext context, Object error) {
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: userMessage(AppLocalizations.of(context), error),
    );
  }

  /// Reports success. Same snackbar surface, same accessibility caveats.
  static void showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;
    showAppSnackBar(context, message: message);
  }
}

/// An inline failure row, for a per-item failure inside a list.
///
/// One row that failed to sync must not replace the other forty-nine, so this is
/// a row state rather than a screen state.
class InlineFailure extends StatelessWidget {
  const InlineFailure({
    required this.error,
    this.onRetry,
    this.retryLabel,
    super.key,
  });

  final Object error;
  final VoidCallback? onRetry;

  /// Null renders [AppLocalizations.actionRetry]. A parameter rather than a
  /// default because a default string in a widget constructor is a literal that
  /// no l10n sweep can find.
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Semantics(
      liveRegion: true,
      child: Row(
        children: <Widget>[
          Icon(
            StatusTone.danger.icon,
            size: 16,
            color: StatusTone.danger.color(colors),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ErrorUtils.userMessage(AppLocalizations.of(context), error),
              style: type.bodySmall?.copyWith(color: colors.danger),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child:
                  Text(retryLabel ?? AppLocalizations.of(context).actionRetry),
            ),
        ],
      ),
    );
  }
}
