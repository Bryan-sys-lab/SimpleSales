/// Single source of truth for the app's brand strings.
///
/// The app was renamed to Simple POS, so the name lives here once instead of
/// being retyped per screen. Two consequences worth knowing about:
///
///  * The Dart package name is still `duka_pos`. Renaming it would rewrite the
///    import prefix in every file in the tree, which is a mechanical change
///    with no user-visible benefit and a large blast radius. The Dart package
///    name is not the product name and never appears to a user.
///  * The platform ids are `com.dukapos.simplepos` on both Android and iOS.
///    That is a new identity, so a 1.x install does not update in place.
///
/// `supportContact` is deliberately empty: an empty string must never render
/// as a "Contact us" affordance with nothing behind it. Callers should test it
/// before showing it.
abstract final class SimplePosBrand {
  /// The product name as shown to a user: app bar, launcher label, about box.
  static const String appName = 'Simple POS';

  /// The registered entity behind [appName]. Same value today; separate
  /// because a trading name and a legal name diverge.
  static const String legalName = 'Simple POS';

  /// Attribution footer. "Nerva" is the vendor, not the app.
  static const String poweredByTag = 'Powered by Nerva';

  /// Where a shop goes for help. Empty until the owner fills it in — the
  /// owner must never have to guess at a support channel.
  static const String supportContact = '';
}
