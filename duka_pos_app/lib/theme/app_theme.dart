import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_haptics.dart';
import 'app_motion.dart';
import 'app_shapes.dart';
import 'app_spacing.dart';
import 'typography.dart';

/// The one place a `ThemeData` is built.
///
/// Both brightnesses are authored by hand. `ColorScheme.fromSeed` is never used
/// for this app's identity: its per-role overrides do not propagate, so
/// overriding `surface` leaves `surfaceContainerHigh` and its eleven siblings
/// holding a tonal palette derived from a seed nobody chose. Owning a product's
/// identity means stating every role that is read — below, that is all of them —
/// and letting Material's own defaults cover the rest.
///

/// The light theme: warm paper, one confident accent.
ThemeData buildDukaLightTheme() => _buildTheme(
      brightness: Brightness.light,
      colors: const AppColors.light(),
    );

/// The dark theme: authored, not flipped.
///
/// The accent moves six steps up its own ramp and the accent *fill* inverts to a
/// light rose, because the brand wine `#6E2638` on a dark surface is 1.80:1 and
/// an auto-flip would have shipped that. Both themes pass AA independently;
/// `test/theme/contrast_test.dart` is the proof, not this comment.
ThemeData buildDukaDarkTheme() => _buildTheme(
      brightness: Brightness.dark,
      colors: const AppColors.dark(),
    );

/// The theme pair. Kept as one call so `MaterialApp` can never be handed one
/// brightness and forget the other.
({ThemeData light, ThemeData dark}) buildDukaThemes() => (
      light: buildDukaLightTheme(),
      dark: buildDukaDarkTheme(),
    );

ThemeData _buildTheme({
  required Brightness brightness,
  required AppColors colors,
}) {
  final AppShapes shapes = buildAppShapes(colors);
  final TextTheme text = AppTypography.scaleFor(colors);
  final ColorScheme scheme = _colorScheme(brightness, colors);
  final AppSpacing spacing = AppSpacing.standard;

  final ThemeData base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: AppTypography.family,
    fontFamilyFallback: AppTypography.fallback,
    textTheme: text,
    // A theme change is a sudden luminance change the user did not cause, and
    // interpolating it is a half-styled state no screen was laid out for. The
    // switch that suppresses it is `MaterialApp.themeAnimationStyle`, not a
    // ThemeData field — see `app.dart`.
    // `visualDensity` is deliberately STANDARD, not `compact`.
    // `VisualDensity.compact` SUBTRACTS from every button's effective minimum
    // size — it turns the 44px floor set below into 36px — and an accessibility
    // floor is not something a density dial gets to spend. Density in this app is
    // expressed through the SPACING TOKENS, where it can be read and adjusted
    // deliberately, rather than through a framework modifier that silently
    // overrides the tap-target minimum everywhere at once.
    //
    // `padded` rather than `shrinkWrap`, so a control that looks compact still
    // keeps its full hit area.
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );

  return base.copyWith(
    scaffoldBackgroundColor: colors.canvas,
    canvasColor: colors.canvas,
    cardColor: colors.surface,
    dividerColor: colors.outline,
    disabledColor: colors.outlineStrong,
    focusColor: colors.accentContainer,
    highlightColor: colors.accentContainer.withValues(alpha: 0.06),
    hoverColor: colors.accentContainer.withValues(alpha: 0.04),
    splashColor: colors.accentContainer.withValues(alpha: 0.10),
    shadowColor: colors.shadow,
    extensions: <ThemeExtension<dynamic>>[
      colors,
      shapes,
      spacing,
      AppMotion.standard,
      HapticTheme.standard,
    ],

    // ------------------------------------------------------------- app bar
    // The app bar is the shell's identity line, so it carries the accent rather
    // than the canvas: it is the one chrome element that says which till this
    // is from across the counter.
    appBarTheme: AppBarTheme(
      backgroundColor: colors.accent,
      foregroundColor: colors.onAccent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(color: colors.onAccent),
      // 48 not 56: this bar sits above a dense data set and every pixel of it is
      // a pixel not spent on a row.
      toolbarHeight: 48,
      titleSpacing: spacing.lg,
      systemOverlayStyle: brightness == Brightness.light
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: colors.surface,
              systemNavigationBarIconBrightness: Brightness.dark,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: colors.surface,
              systemNavigationBarIconBrightness: Brightness.light,
            ),
      iconTheme: IconThemeData(color: colors.onAccent, size: 22),
      actionsIconTheme: IconThemeData(color: colors.onAccent, size: 22),
    ),

    // -------------------------------------------------------------- cards
    // Elevation 0 plus a hairline edge. A card on a warm canvas separated by a
    // shadow alone is a smudge; the edge is what actually draws the boundary.
    cardTheme: CardThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: shapes.card(colors),
    ),

    // ------------------------------------------------------------- inputs
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      // `outlineStrong` clears 3:1 against the surface, which is what an input
      // edge is: a meaningful boundary the user must find. `outline` would not.
      hintStyle: text.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
      labelStyle: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
      floatingLabelStyle: text.labelMedium?.copyWith(color: colors.accent),
      helperStyle: text.bodySmall,
      errorStyle: text.bodySmall?.copyWith(color: colors.danger),
      contentPadding: EdgeInsetsDirectional.only(
        start: spacing.md,
        end: spacing.md,
        top: spacing.md,
        // Enough for a 13sp label that has floated up, so the floating label
        // never overlaps the value at large text scales.
        bottom: spacing.md + 4,
      ),
      border: OutlineInputBorder(
        borderRadius: shapes.controlRadius,
        borderSide: BorderSide(color: colors.outlineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: shapes.controlRadius,
        borderSide: BorderSide(color: colors.outlineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: shapes.controlRadius,
        borderSide: BorderSide(color: colors.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: shapes.controlRadius,
        borderSide: BorderSide(color: colors.danger, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: shapes.controlRadius,
        borderSide: BorderSide(color: colors.danger, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: shapes.controlRadius,
        borderSide: BorderSide(color: colors.outline),
      ),
      prefixIconColor: colors.onSurfaceMuted,
      suffixIconColor: colors.onSurfaceMuted,
    ),

    // ------------------------------------------------------------ buttons
    // The 44 floor is honoured through `minimumSize` AND
    // `MaterialTapTargetSize.padded` above: a dense visual height of 40 with
    // padded hit testing keeps the row tight while the target stays legal.
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll<Size>(
          Size(0, spacing.minTapTarget),
        ),
        padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsetsDirectional.symmetric(horizontal: spacing.lg),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: shapes.controlRadius)),
        elevation: const WidgetStatePropertyAll<double>(0),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll<Size>(
          Size(0, spacing.minTapTarget),
        ),
        padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsetsDirectional.symmetric(horizontal: spacing.lg),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: shapes.controlRadius)),
        backgroundColor: WidgetStatePropertyAll<Color>(colors.surface),
        foregroundColor: WidgetStatePropertyAll<Color>(colors.onSurface),
        elevation: WidgetStatePropertyAll<double>(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll<Size>(
          Size(0, spacing.minTapTarget),
        ),
        padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsetsDirectional.symmetric(horizontal: spacing.lg),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: shapes.controlRadius)),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: colors.outlineStrong),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll<Size>(
          Size(0, spacing.minTapTarget),
        ),
        padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsetsDirectional.symmetric(horizontal: spacing.md),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: shapes.controlRadius)),
      ),
    ),
    // The destructive variant: same silhouette, danger fill, and a name that
    // says the verb rather than "OK".
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll<Size>(const Size(44, 44)),
        foregroundColor: WidgetStatePropertyAll<Color>(colors.onSurfaceVariant),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: shapes.controlRadius)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll<Size>(const Size(0, 40)),
        textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelMedium),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: shapes.controlRadius)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.accent,
      foregroundColor: colors.onAccent,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: shapes.cardRadius),
    ),

    // ------------------------------------------------------- navigation
    // One width-to-affordance map lives in the shell (lib/routing/shell.dart).
    // These are the visual halves of it.
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      elevation: 0,
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.accentContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: shapes.chipRadius,
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
        (Set<WidgetState> states) => text.labelMedium!.copyWith(
          color: states.contains(WidgetState.selected)
              ? colors.accent
              : colors.onSurfaceMuted,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
        (Set<WidgetState> states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? colors.accent
              : colors.onSurfaceMuted,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.accentContainer,
      selectedLabelTextStyle: text.labelMedium?.copyWith(color: colors.accent),
      unselectedLabelTextStyle:
          text.labelMedium?.copyWith(color: colors.onSurfaceMuted),
      selectedIconTheme: IconThemeData(color: colors.accent, size: 22),
      unselectedIconTheme:
          IconThemeData(color: colors.onSurfaceMuted, size: 22),
      useIndicator: true,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      width: 280,
    ),

    // ---------------------------------------------------------- overlays
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.onSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: colors.canvas),
      actionTextColor: colors.onSurface,
      // The floating snackbar sits above the nav bar on a compact layout; this
      // is the minimum clear space it needs to not cover a thumb target.
      insetPadding: EdgeInsets.all(spacing.lg),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: shapes.cardRadius),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
      shape: shapes.surface(colors),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: colors.scrim,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: colors.outlineStrong,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(shapes.lg)),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(colors.surfaceRaised),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
        elevation: const WidgetStatePropertyAll<double>(0),
        shape: WidgetStatePropertyAll<OutlinedBorder>(shapes.surface(colors)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: shapes.surface(colors),
      textStyle: text.bodyMedium,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.onSurface,
        borderRadius: BorderRadius.circular(shapes.sm),
      ),
      textStyle: text.bodySmall?.copyWith(color: colors.canvas),
      // Short: a tooltip on a till should name the control, not explain it.
      waitDuration: const Duration(milliseconds: 600),
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: colors.surfaceRaised,
      contentTextStyle: text.bodyMedium,
      elevation: 0,
    ),

    // ----------------------------------------------------------- controls
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? colors.onAccent
            : colors.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? colors.accent
            : colors.surfaceSunken,
      ),
      trackOutlineColor: WidgetStatePropertyAll<Color>(colors.outlineStrong),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: colors.outlineStrong, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? colors.accent
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll<Color>(colors.onAccent),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) => states.contains(WidgetState.selected)
            ? colors.accent
            : colors.outlineStrong,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.surfaceSunken,
      selectedColor: colors.accentContainer,
      checkmarkColor: colors.onAccentContainer,
      side: BorderSide(color: colors.outline),
      labelStyle: text.labelMedium!,
      secondaryLabelStyle: text.labelMedium!,
      shape: RoundedRectangleBorder(borderRadius: shapes.chipRadius),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outline,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      // 44 minimum via `minVerticalPadding` plus `visualDensity.compact`, which
      // is the only combination that keeps a two-line row legal and tight.
      minVerticalPadding: 8,
      dense: true,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall,
      iconColor: colors.onSurfaceMuted,
      shape: RoundedRectangleBorder(borderRadius: shapes.controlRadius),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: colors.surfaceSunken,
      circularTrackColor: colors.surfaceSunken,
      linearMinHeight: 4,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: colors.accent,
      inactiveTrackColor: colors.surfaceSunken,
      thumbColor: colors.accent,
      overlayColor: colors.accentContainer,
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle:
          text.labelMedium?.copyWith(color: colors.onSurfaceMuted),
      dataTextStyle: text.bodyMedium,
      dividerThickness: 1,
      headingRowColor: WidgetStatePropertyAll<Color?>(colors.surfaceSunken),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll<Color>(colors.outlineStrong),
      radius: const Radius.circular(4),
      thickness: const WidgetStatePropertyAll<double>(6),
    ),
  );
}

/// A hand-authored [ColorScheme].
///
/// `secondary` and `tertiary` are deliberately NOT a second hue. This app has
/// one accent, and a component that reads `secondary` (a FAB's container, some
/// chips, a tonal surface) should get a quieter version of the same accent
/// rather than inventing a companion colour nobody chose. Every role below is
/// measured in `test/theme/contrast_test.dart`.
ColorScheme _colorScheme(Brightness brightness, AppColors c) {
  final bool light = brightness == Brightness.light;

  return ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    primaryContainer: c.accentContainer,
    onPrimaryContainer: c.onAccentContainer,
    secondary: c.accent,
    onSecondary: c.onAccent,
    secondaryContainer: c.accentContainer,
    onSecondaryContainer: c.onAccentContainer,
    tertiary: c.onSurfaceVariant,
    onTertiary: c.surface,
    tertiaryContainer: c.surfaceSunken,
    onTertiaryContainer: c.onSurface,
    error: c.danger,
    onError: c.onAccent,
    errorContainer: c.dangerContainer,
    onErrorContainer: c.onDangerContainer,
    surface: c.surface,
    onSurface: c.onSurface,
    onSurfaceVariant: c.onSurfaceVariant,
    // The container ladder. Material's own defaults would derive these from a
    // seed and land nowhere near the paper/canvas ladder this app is built on.
    surfaceContainerLowest: light ? const Color(0xFFFFFFFF) : c.surfaceSunken,
    surfaceContainerLow: light ? c.canvas : const Color(0xFF191315),
    surfaceContainer: light ? c.canvas : const Color(0xFF1D181A),
    surfaceContainerHigh: light ? c.surfaceSunken : c.surfaceRaised,
    surfaceContainerHighest: light ? c.surfaceSunken : const Color(0xFF3A3234),
    surfaceDim: light ? c.surfaceSunken : const Color(0xFF191315),
    surfaceBright: light ? c.surface : c.surfaceRaised,
    surfaceTint: c.accent,
    // Hairline, and its stronger sibling for meaningful boundaries.
    outline: c.outlineStrong,
    outlineVariant: c.outline,
    shadow: c.shadow,
    scrim: c.scrim,
    inverseSurface: c.onSurface,
    onInverseSurface: c.canvas,
    inversePrimary: light ? const Color(0xFFE86885) : const Color(0xFF6E2638),
  );
}
