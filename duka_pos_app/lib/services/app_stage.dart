/// Which top-level screen the app is showing.
///
/// Deliberately a pure function rather than a chain of `if` statements inside a
/// widget: the rule that a cashier must always be able to reach the PIN pad is
/// a security-relevant routing decision, and it needs to be assertable without
/// booting an app or touching a database.
enum AppStage {
  /// Reading local state. The branded splash, never a blank frame.
  loading,

  /// The local database could not be opened. Offers restore/reinstall.
  databaseFailed,

  /// A shop exists on this till but nobody is signed in.
  ///
  /// This is the chooser: "Set up another shop" or "Sign in". It replaced a
  /// flow where a till that had no shop went straight to owner setup, so a
  /// cashier opening a brand-new device saw an admin's setup form — the screen
  /// addressed to whoever is installing the app, on the screen every user is
  /// forced through.
  chooser,

  /// Inside "sign in": the list of people and the PIN pad.
  signingIn,

  /// Inside "set up": creating the shop owner.
  settingUp,

  /// Signed in, and this till has not yet seen the first-run walkthrough.
  onboarding,

  /// Signed in, past the walkthrough, and the till has not yet asked for the
  /// permissions it can use.
  ///
  /// AFTER the walkthrough and BEFORE the shop, and it is where the app asks
  /// for the camera and for Bluetooth — once, in one place, where the owner is
  /// not in the middle of a sale.
  ///
  /// It CANNOT BLOCK: it is admin-only, it is asked once per workspace, and
  /// the screen's own "Continue" is always there. A till that cannot sell
  /// because nobody granted a permission it does not need is a broken till.
  permissions,

  /// Signed in and past the walkthrough. The shop itself.
  ready,
}

/// Resolves the current stage from the app's state.
///
/// Three rules here are load-bearing:
///
/// * [AppStage.signingIn] outranks [AppStage.onboarding]. The walkthrough is
///   guidance, not a gate. When it was checked first, a till whose walkthrough
///   had not been dismissed — a newly provisioned till, or one whose workspace
///   had been switched — stranded every user, cashier included, on the welcome
///   screens with no way to reach the PIN pad. Authentication is checked before
///   anything optional, always.
///
/// * The walkthrough is admin-only. Its copy is addressed to whoever set the
///   shop up ("the email you entered", "add cashiers in Settings"), so showing
///   it to a cashier is both confusing and a small information leak about how
///   the shop is configured. A cashier goes straight to the shop; an admin sees
///   it once.
///
/// * [chooser] covers both "no shop yet" and "shop exists, nobody signed in".
///   The chooser screen itself decides whether to offer shop setup, because that
///   depends on whether a shop exists — a fact the router already knows but that
///   is not part of the security-relevant ordering.
///
/// * The permissions step comes AFTER the walkthrough and is ADMIN-ONLY, like
///   the walkthrough. Its copy is addressed to whoever set the shop up, and a
///   cashier must never be routed into a step that talks about "your till".
///   It is also asked ONCE per workspace: a permission the owner has already
///   answered is a decision, and a till that asks again every morning is a till
///   people learn to dismiss without reading.
AppStage resolveAppStage({
  required bool isLoading,
  required bool hasDatabaseFailure,
  required bool hasShop,
  required bool isSignedIn,
  required bool isAdmin,
  required bool onboardingComplete,
  bool permissionsAsked = true,
  AppChooserIntent chooserIntent = AppChooserIntent.signIn,
}) {
  if (isLoading) return AppStage.loading;
  if (hasDatabaseFailure) return AppStage.databaseFailed;

  if (!isSignedIn) {
    if (!hasShop) {
      if (chooserIntent == AppChooserIntent.signIn) return AppStage.chooser;
      return AppStage.settingUp;
    }
    switch (chooserIntent) {
      case AppChooserIntent.signIn:
        return AppStage.signingIn;
      case AppChooserIntent.setUp:
        return AppStage.settingUp;
      case AppChooserIntent.addShop:
        return AppStage.settingUp;
    }
  }

  if (!onboardingComplete && isAdmin) return AppStage.onboarding;
  if (!permissionsAsked && isAdmin) return AppStage.permissions;
  return AppStage.ready;
}

/// What the chooser is currently offering.
///
/// A field on the router rather than local state inside the chooser, because the
/// router has to resolve which screen the chooser's choice leads to. Passing it
/// as a parameter rather than reading it from a `ValueNotifier` inside a widget
/// is what keeps [resolveAppStage] a pure function and therefore testable.
enum AppChooserIntent {
  /// "Sign in" — the default whenever a shop exists.
  signIn,

  /// "Set up this shop" — the owner creating the first account.
  setUp,

  /// "Add another shop" — from Settings, on a device that already has a shop.
  addShop,
}
