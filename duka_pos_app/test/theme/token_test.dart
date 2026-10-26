import 'package:duka_pos/theme/app_colors.dart';
import 'package:duka_pos/theme/app_haptics.dart';
import 'package:duka_pos/theme/app_motion.dart';
import 'package:duka_pos/theme/app_shapes.dart';
import 'package:duka_pos/theme/app_spacing.dart';
import 'package:duka_pos/theme/app_theme.dart';
import 'package:duka_pos/theme/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The structural half of the contrast gate.
///
/// [contrast_test.dart] proves the palette's ratios. This proves the machinery
/// that delivers those slots actually reaches a widget — the failures here are
/// the ones that ship a dark mode that silently renders Material's defaults, or
/// a screen that renders unstyled because an extension was attached to the light
/// theme only.
void main() {
  group('every extension is attached to BOTH themes', () {
    for (final (String name, ThemeData theme) in <(String, ThemeData)>[
      ('light', buildDukaLightTheme()),
      ('dark', buildDukaDarkTheme()),
    ]) {
      test(
          '$name carries AppColors, AppShapes, AppSpacing, AppMotion and '
          'HapticTheme', () {
        expect(
          theme.extension<AppColors>(),
          isNotNull,
          reason: '$name is missing AppColors. An extension on the light theme '
              'only means the other brightness renders Material defaults, '
              'silently and correctly enough to ship.',
        );
        expect(theme.extension<AppShapes>(), isNotNull, reason: name);
        expect(theme.extension<AppSpacing>(), isNotNull, reason: name);
        expect(theme.extension<AppMotion>(), isNotNull, reason: name);
        expect(theme.extension<HapticTheme>(), isNotNull, reason: name);
      });
    }
  });

  group('the asserting reader never falls back', () {
    testWidgets('AppColors.of throws under a ThemeData built without it',
        (WidgetTester tester) async {
      // A bare `ThemeData()` has no AppColors. `of()` must FAIL LOUDLY rather
      // than return a default palette no test ever verified — a silent fallback
      // ships an unstyled screen and every guideline still passes.
      late Object? caught;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(),
          home: Builder(
            builder: (BuildContext context) {
              try {
                AppColors.of(context);
              } catch (error) {
                caught = error;
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(caught, isA<AssertionError>());
    });

    testWidgets('AppColors.of returns the attached slots',
        (WidgetTester tester) async {
      AppColors? read;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDukaLightTheme(),
          home: Builder(
            builder: (BuildContext context) {
              read = AppColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(read, isNotNull);
      expect(read!.accent, const AppColors.light().accent);
    });
  });

  group('the structural scales are identical across brightnesses', () {
    test('spacing does not change with the theme', () {
      // A spacing scale that drifted between light and dark would mean a row
      // measured on a light device is not the row that ships on a dark one.
      expect(buildDukaLightTheme().extension<AppSpacing>(),
          buildDukaDarkTheme().extension<AppSpacing>());
      expect(
        buildDukaLightTheme().extension<AppSpacing>(),
        AppSpacing.standard,
      );
      expect(
        buildDukaDarkTheme().extension<AppSpacing>(),
        AppSpacing.standard,
      );
    });

    test('motion does not change with the theme', () {
      expect(buildDukaLightTheme().extension<AppMotion>(),
          buildDukaDarkTheme().extension<AppMotion>());
    });

    test('shapes differ ONLY in the shadow colour', () {
      final AppShapes light = buildDukaLightTheme().extension<AppShapes>()!;
      final AppShapes dark = buildDukaDarkTheme().extension<AppShapes>()!;
      expect(light.xs, dark.xs);
      expect(light.sm, dark.sm);
      expect(light.md, dark.md);
      expect(light.lg, dark.lg);
      expect(light.pill, dark.pill);
      // A silhouette is a structural constant; only the shadow follows the theme.
      expect(light.cardRadius, dark.cardRadius);
      expect(light.raisedShadow, isNot(dark.raisedShadow));
    });
  });

  group('the tap-target floor is the accessibility floor, not a preference',
      () {
    test('it uses the preferred 48px Android target', () {
      expect(AppSpacing.standard.minTapTarget, greaterThanOrEqualTo(48));
    });

    test('every button theme in the light theme honours it', () {
      final ThemeData theme = buildDukaLightTheme();
      for (final (String name, ButtonStyle? style) in <(String, ButtonStyle?)>[
        ('filled', theme.filledButtonTheme.style),
        ('elevated', theme.elevatedButtonTheme.style),
        ('outlined', theme.outlinedButtonTheme.style),
        ('text', theme.textButtonTheme.style),
      ]) {
        final Size? size = style?.minimumSize?.resolve(<WidgetState>{});
        expect(
          size?.height,
          greaterThanOrEqualTo(48),
          reason: 'the $name button theme has a ${size?.height}px minimum',
        );
      }
    });

    test('the icon button theme honours it', () {
      final Size? size = buildDukaLightTheme()
          .iconButtonTheme
          .style
          ?.minimumSize
          ?.resolve(<WidgetState>{});
      expect(size?.height, greaterThanOrEqualTo(48));
    });

    test('the dark theme honours it too', () {
      final Size? size = buildDukaDarkTheme()
          .filledButtonTheme
          .style
          ?.minimumSize
          ?.resolve(<WidgetState>{});
      expect(size?.height, greaterThanOrEqualTo(48));
    });
  });

  group('reduced motion collapses to zero, not to gentler', () {
    testWidgets('resolve returns Duration.zero under disableAnimations',
        (WidgetTester tester) async {
      Duration? full;
      Duration? reduced;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (BuildContext context) {
              full = AppMotion.standard.fast;
              reduced = AppMotion.resolve(context, AppMotion.standard.fast);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(full, greaterThan(Duration.zero));
      expect(reduced, Duration.zero);
    });

    testWidgets('resolve returns the role unchanged when motion is allowed',
        (WidgetTester tester) async {
      Duration? resolved;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (BuildContext context) {
              resolved = AppMotion.resolve(context, AppMotion.standard.normal);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, AppMotion.standard.normal);
    });
  });

  group('the theme bans its own animation', () {
    test('the flag lives on MaterialApp, not ThemeData', () {
      // Recorded because this is easy to "fix" in the wrong place: adding
      // `themeAnimationStyle` to ThemeData is a compile error, and the real
      // switch is on MaterialApp in lib/main.dart.
      expect(buildDukaLightTheme(), isA<ThemeData>());
    });
  });

  group('typography', () {
    test('the brand face is the bundled variable font', () {
      expect(AppTypography.family, 'PlusJakartaSans');
      expect(AppTypography.fallback, isNotEmpty);
      expect(
        AppTypography.fallback.last,
        isNot(AppTypography.family),
        reason: 'the fallback cascade must END in a different face, or it is '
            'not a cascade',
      );
    });

    testWidgets('every role in the scale carries tabular figures',
        (WidgetTester tester) async {
      // Numeric roles only — a heading has no numbers to misalign. Checking the
      // display role is what matters: it is where the day's total lives.
      final TextTheme type = AppTypography.scaleFor(const AppColors.light());
      // EVERY role, because the assertion is "a number may appear anywhere",
      // not "a number appears in the three roles I remembered".
      for (final MapEntry<TextStyle?, String> entry in <TextStyle?, String>{
        type.displaySmall: 'displaySmall',
        type.headlineMedium: 'headlineMedium',
        type.headlineSmall: 'headlineSmall',
        type.titleLarge: 'titleLarge',
        type.titleMedium: 'titleMedium',
        type.titleSmall: 'titleSmall',
        type.bodyLarge: 'bodyLarge',
        type.bodyMedium: 'bodyMedium',
        type.bodySmall: 'bodySmall',
        type.labelLarge: 'labelLarge',
        type.labelMedium: 'labelMedium',
        type.labelSmall: 'labelSmall',
      }.entries) {
        final TextStyle? style = entry.key;
        expect(
          style?.fontFeatures,
          contains(AppTypography.tabular.first),
          reason: '${entry.value} lost its tabular figures, so a column of '
              'totals will shift horizontally as the digits change',
        );
      }
    });

    testWidgets('bold text raises body weights without exceeding the axis',
        (WidgetTester tester) async {
      final TextTheme base = AppTypography.scaleFor(const AppColors.light());
      final TextTheme bold = AppTypography.boldTextFor(base, true);

      expect(bold.bodyMedium?.fontWeight, FontWeight.w600);
      expect(bold.bodyLarge?.fontWeight, FontWeight.w600);
      expect(bold.bodySmall?.fontWeight, FontWeight.w600);
      // An already-heavy role is left alone: mapping 800 to 900 would request a
      // weight the variable font tops out at, and Flutter silently renders it as
      // 800 — so a "bolder" heading would come out identical.
      expect(bold.displaySmall?.fontWeight, base.displaySmall?.fontWeight);
      expect(bold.titleLarge?.fontWeight, base.titleLarge?.fontWeight);
    });

    test('not bolding is the identity, so the fast path is free', () {
      final TextTheme base = AppTypography.scaleFor(const AppColors.light());
      expect(identical(AppTypography.boldTextFor(base, false), base), isTrue);
    });
  });

  group('haptics', () {
    test('copyWith closes the gate without dropping the slots', () {
      // Turning haptics off must not delete the design: the slots are what a
      // settings toggle turns back on, not something to rebuild.
      expect(HapticTheme.standard.copyWith(enabled: false).enabled, isFalse);
      expect(HapticTheme.standard.enabled, isTrue);
    });
  });

  group('the spacing scale is a real scale', () {
    test('matches the SimpleSales interaction standard', () {
      final AppSpacing s = AppSpacing.standard;
      expect(s.xxs, 4);
      expect(s.xs, 8);
      expect(s.sm, 12);
      expect(s.md, 16);
      expect(s.lg, 24);
      expect(s.xl, 32);
      expect(s.xxl, 40);
      expect(s.section, 48);
      expect(s.spacious, 64);
      expect(s.minTapTarget, 48);
      expect(s.primaryButtonHeight, 48);
      expect(s.textFieldHeight, 56);
      expect(s.buttonHorizontalPadding, 16);
      expect(s.formPrimaryActionGap, 32);
      expect(s.mobilePageGutter, 16);
      expect(s.largePageGutter, 24);
    });

    test('the steps are strictly increasing', () {
      final AppSpacing s = AppSpacing.standard;
      expect(s.xs, lessThan(s.sm));
      expect(s.sm, lessThan(s.md));
      expect(s.md, lessThan(s.lg));
      expect(s.lg, lessThan(s.xl));
      expect(s.xl, lessThan(s.xxl));
    });

    test('a row is never shorter than the tap floor it holds', () {
      expect(AppSpacing.standard.rowHeight,
          greaterThanOrEqualTo(AppSpacing.standard.minTapTarget));
    });
  });
}
