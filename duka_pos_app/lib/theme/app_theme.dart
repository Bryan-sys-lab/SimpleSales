import 'package:flutter/material.dart';

/// Duka POS visual language: a calm counter ledger with one confident accent.
/// Keep screen-level styling inside these tokens so the app feels like one tool.
abstract final class DukaColors {
  static const ink = Color(0xFF251A1D);
  static const mutedInk = Color(0xFF66575B);
  static const canvas = Color(0xFFF8F5F1);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceWarm = Color(0xFFF1EAE5);
  static const primary = Color(0xFF6E2638);
  static const primaryDark = Color(0xFF4B1725);
  static const onPrimary = Color(0xFFFFFFFF);
  static const success = Color(0xFF176B4D);
  static const warning = Color(0xFF9A5B00);
  static const danger = Color(0xFFB3261E);
  static const outline = Color(0xFFD6C9C4);
}

abstract final class DukaSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

ThemeData buildDukaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: DukaColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: DukaColors.primary,
    onPrimary: DukaColors.onPrimary,
    surface: DukaColors.surface,
    onSurface: DukaColors.ink,
    outline: DukaColors.outline,
    error: DukaColors.danger,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: DukaColors.canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: DukaColors.primary,
      foregroundColor: DukaColors.onPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: DukaColors.onPrimary),
    ),
    textTheme: base.textTheme.copyWith(
      headlineSmall: const TextStyle(
          fontSize: 24,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: DukaColors.ink),
      titleLarge: const TextStyle(
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: DukaColors.ink),
      titleMedium: const TextStyle(
          fontSize: 16,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: DukaColors.ink),
      bodyLarge:
          const TextStyle(fontSize: 16, height: 1.45, color: DukaColors.ink),
      bodyMedium:
          const TextStyle(fontSize: 14, height: 1.4, color: DukaColors.ink),
      bodySmall: const TextStyle(
          fontSize: 12, height: 1.35, color: DukaColors.mutedInk),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: DukaColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DukaColors.surface,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: DukaSpacing.lg, vertical: DukaSpacing.md),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: DukaColors.outline)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: DukaColors.outline)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: DukaColors.primary, width: 2)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: DukaSpacing.lg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: DukaSpacing.lg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: DukaColors.surface,
      indicatorColor: DukaColors.surfaceWarm,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? DukaColors.primary
                : DukaColors.mutedInk,
          )),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
