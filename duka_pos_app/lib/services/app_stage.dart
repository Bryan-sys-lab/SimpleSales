/// Which top-level screen the app is showing.
///
/// This is deliberately a pure function rather than a chain of `if` statements
/// inside a widget: the rule that a cashier must always be able to reach the
/// PIN pad is a security-relevant routing decision, and it needs to be
/// assertable without booting an app or touching a database.
enum AppStage {
  /// Reading local state. Shows a progress indicator, never a blank frame.
  loading,

  /// The local database could not be opened. Offers restore/reinstall.
  databaseFailed,

  /// No shop exists on this till yet. Offers till setup.
  getStarted,

  /// A shop exists but nobody is signed in. The PIN pad.
  locked,

  /// Signed in, and this till has not yet seen the first-run walkthrough.
  onboarding,

  /// Signed in and past the walkthrough. The shop itself.
  ready,
}

/// Resolves the current stage from the app's state.
///
/// Two rules here are load-bearing:
///
/// * [AppStage.locked] outranks [AppStage.onboarding]. The walkthrough is
///   guidance, not a gate. When it was checked first, a till whose walkthrough
///   had not been dismissed — a newly provisioned till, or one whose workspace
///   had been switched — stranded every user, cashier included, on the welcome
///   screens with no way to reach the PIN pad. Authentication is checked before
///   anything optional, always.
///
/// * The walkthrough is admin-only. Its copy is addressed to whoever set the
///   shop up ("the email you entered", "add cashiers in Settings"), so showing
///   it to a cashier is both confusing and a small information leak about how
///   the shop is configured. A cashier goes straight to the shop; the admin sees
///   it once.
AppStage resolveAppStage({
  required bool isLoading,
  required bool hasDatabaseFailure,
  required bool hasShop,
  required bool isSignedIn,
  required bool isAdmin,
  required bool onboardingComplete,
}) {
  if (isLoading) return AppStage.loading;
  if (hasDatabaseFailure) return AppStage.databaseFailed;

  // Without a shop there is no staff roster and no PIN hash to check against,
  // so there is nothing to sign in to. This is till setup, not a login failure.
  if (!hasShop) return AppStage.getStarted;

  if (!isSignedIn) return AppStage.locked;
  if (!onboardingComplete && isAdmin) return AppStage.onboarding;
  return AppStage.ready;
}