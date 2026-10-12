/// Single source of truth for the app's brand strings.
///
/// The app was renamed to SimpleSales, so the name lives here once instead of
/// being retyped per screen. Two consequences worth knowing about:
///
///  * The Dart package name is still `duka_pos`. Renaming it would rewrite the
///    import prefix in every file in the tree, which is a mechanical change
///    with no user-visible benefit and a large blast radius. The Dart package
///    name is not the product name and never appears to a user.
///  * The platform ids are `com.dukapos.simplepos` on both Android and iOS.
///    That is a new identity, so a 1.x install does not update in place.
abstract final class SimplePosBrand {
  /// The product name as shown to a user: app bar, launcher label, about box.
  ///
  /// One word, no space. "SimpleSales" reads as a single product name the way
  /// "WordPress" and "Salesforce" do, and it survives being dropped into a
  /// sentence without a hyphen appearing in the middle of it.
  static const String appName = 'SimpleSales';

  /// Attribution footer. "Nerva" is the vendor, not the app.
  static const String poweredByTag = 'Powered by Nerva';
}
