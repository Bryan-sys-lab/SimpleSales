import 'package:material_ui/material_ui.dart';

import '../profile/shop_profile.dart';
import 'primitives.dart';

@immutable
class DashboardProfilePalette {
  const DashboardProfilePalette({
    required this.accent,
    required this.tint,
    required this.ink,
  });

  final Color accent;
  final Color tint;
  final Color ink;

  static DashboardProfilePalette forProfile(
    ShopProfile profile, {
    required Brightness brightness,
  }) {
    final bool dark = brightness == Brightness.dark;
    // Profiles keep their own iconography and language. Shared dashboard
    // actions and identity tints use the shared forest palette so the main views
    // stay visually coherent with the app's brand tokens.
    return DashboardProfilePalette(
      accent: dark ? Primitives.electric : Primitives.forest,
      tint: dark ? Primitives.surfaceGreenDark : Primitives.surfaceGreen,
      ink: dark ? Primitives.surfaceElectricStrong : Primitives.forest,
    );
  }
}
