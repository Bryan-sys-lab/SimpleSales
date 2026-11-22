import '../l10n/generated/app_localizations.dart';
import '../services/backend_service.dart';

String verificationFailureMessage(
  AppLocalizations l10n,
  VerificationException error,
) =>
    switch (error.failure) {
      VerificationFailure.notConfigured => l10n.settingsVerifyNotConfigured,
      VerificationFailure.identityUnavailable =>
        l10n.settingsVerifyIdentityUnavailable,
      VerificationFailure.emailUnavailable => l10n.settingsVerifyEmailFailed,
      VerificationFailure.expired => l10n.settingsVerifyCodeExpired,
      VerificationFailure.tooManyAttempts => l10n.settingsVerifyCodeBurnt,
      VerificationFailure.tooManyCodes => l10n.settingsVerifyTooManyCodes,
      VerificationFailure.invalidVoucher => l10n.signupPaywallVoucherInvalid,
      VerificationFailure.shopSetupRequired => l10n.settingsVerifyShopMissing,
      VerificationFailure.invalidCode => error.attemptsRemaining == null
          ? l10n.settingsVerifyCodeWrong(1)
          : l10n.settingsVerifyCodeWrong(error.attemptsRemaining!),
      VerificationFailure.network => l10n.settingsIdentityLinkFailed,
      VerificationFailure.unknown => l10n.settingsIdentityLinkFailed,
    };
