import 'package:flutter/material.dart';

import '../profile/shop_profile.dart';

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
    return switch (profile) {
      ShopProfile.duka => DashboardProfilePalette(
          accent: Color(dark ? 0xFFF59E0B : 0xFFD97706),
          tint: Color(dark ? 0xFF3A2A12 : 0xFFFEF3C7),
          ink: Color(dark ? 0xFFFCDFA0 : 0xFF92400E),
        ),
      ShopProfile.fashion => DashboardProfilePalette(
          accent: Color(dark ? 0xFFE08E75 : 0xFFC26D53),
          tint: Color(dark ? 0xFF38241F : 0xFFFAF0EC),
          ink: Color(dark ? 0xFFFFC1AD : 0xFF7C3F2C),
        ),
      ShopProfile.drinks => DashboardProfilePalette(
          accent: Color(dark ? 0xFFFB923C : 0xFFEA580C),
          tint: Color(dark ? 0xFF3B2719 : 0xFFFFEDD5),
          ink: Color(dark ? 0xFFFFC18A : 0xFF9A3412),
        ),
      ShopProfile.open => DashboardProfilePalette(
          accent: Color(dark ? 0xFF38BDF8 : 0xFF0284C7),
          tint: Color(dark ? 0xFF142F3B : 0xFFE0F2FE),
          ink: Color(dark ? 0xFFA7E2FF : 0xFF075985),
        ),
    };
  }
}
