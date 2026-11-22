// The email check that stands in front of creating a shop.
//
// A shop is created only once the person has proved they can read the address
// they gave. This is the one place that does it, so first-run setup and "add
// another shop" cannot drift apart: request the code, take it in a sheet that
// cannot be dismissed by accident, and hand back what the server accepted.
//
// It changes nothing on the device. The caller creates the shop and then applies
// the result with `BackendService.adoptPendingVerification`.

import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/backend_service.dart';
import '../../services/pin_reset_service.dart';
import '../verification_message.dart';
import 'verify_identity_dialog.dart';

/// How the check ended.
class VerificationGateResult {
  const VerificationGateResult.accepted(PendingVerification value)
      : pending = value,
        message = null;

  /// The person backed out. Nothing was created and nothing is wrong.
  const VerificationGateResult.cancelled()
      : pending = null,
        message = null;

  /// The code could not be requested. [message] says why, in the person's
  /// language, and the shop is not created.
  const VerificationGateResult.failed(String reason)
      : pending = null,
        message = reason;

  final PendingVerification? pending;
  final String? message;

  bool get isAccepted => pending != null;
  bool get isFailed => message != null;
}

void _logUnexpectedVerificationSetupError(
  String stage,
  Object error,
  StackTrace stack,
) {
  debugPrint(
    'Unexpected verification setup error at $stage: '
    '${error.runtimeType}\n$stack',
  );
}

/// Emails a code to [email], takes it, and returns the accepted session.
///
/// [pin] is the PIN the shop will have; the server binds it into the challenge
/// exactly as it does for the Settings flow.
Future<VerificationGateResult> verifyEmailBeforeCreate(
  BuildContext context, {
  required String email,
  required String pin,
  required String shopName,
  required String ownerName,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final VerificationChallenge challenge;
  try {
    challenge = await BackendService.requestVerificationCode(
      email: email,
      pin: pin,
      shopName: shopName,
      ownerName: ownerName,
    );
  } on VerificationException catch (error) {
    return VerificationGateResult.failed(
      verificationFailureMessage(l10n, error),
    );
  } catch (error, stack) {
    _logUnexpectedVerificationSetupError('request-code', error, stack);
    return VerificationGateResult.failed(l10n.settingsIdentityLinkFailed);
  }
  if (!context.mounted) return const VerificationGateResult.cancelled();

  // MASKED: the sheet is read with people standing nearby.
  final String masked = challenge.maskedEmail.isNotEmpty
      ? challenge.maskedEmail
      : PinResetService.maskEmail(email);

  PendingRegistration? codeAccepted;
  final bool confirmed = await showVerifyCodeSheet(
    context,
    maskedEmail: masked,
    dismissible: false,
    onSubmit: (String code) async {
      try {
        codeAccepted = await BackendService.confirmVerificationCodeDeferred(
          email: email,
          pin: pin,
          code: code,
          shopName: shopName,
          ownerName: ownerName,
        );
        return null;
      } on VerificationException catch (error) {
        return verificationFailureMessage(l10n, error);
      } catch (error, stack) {
        _logUnexpectedVerificationSetupError('verify-code', error, stack);
        return l10n.settingsIdentityLinkFailed;
      }
    },
    onResend: () async {
      try {
        await BackendService.requestVerificationCode(
          email: email,
          pin: pin,
          shopName: shopName,
          ownerName: ownerName,
        );
        return l10n.settingsVerifyCodeSent(masked);
      } on VerificationException catch (error) {
        return verificationFailureMessage(l10n, error);
      } catch (error, stack) {
        _logUnexpectedVerificationSetupError('resend-code', error, stack);
        return l10n.settingsIdentityLinkFailed;
      }
    },
  );

  final PendingRegistration? registration = codeAccepted;
  if (!confirmed || registration == null || !context.mounted) {
    return const VerificationGateResult.cancelled();
  }

  try {
    final PendingVerification completed =
        await BackendService.completePendingVerification(
      registration: registration,
    );
    if (!context.mounted) return const VerificationGateResult.cancelled();
    return VerificationGateResult.accepted(completed);
  } on VerificationException catch (error) {
    return VerificationGateResult.failed(
      verificationFailureMessage(l10n, error),
    );
  } catch (error, stack) {
    _logUnexpectedVerificationSetupError('complete-registration', error, stack);
    return VerificationGateResult.failed(l10n.settingsIdentityLinkFailed);
  }
}
