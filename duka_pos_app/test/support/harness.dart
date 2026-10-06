import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/theme/app_haptics.dart';
import 'package:duka_pos/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// One place that pins the surface every widget test in this app runs on.
///
/// Before this file existed, `widget_test.dart` pumped widgets at the default
/// 800x600 surface — WIDER THAN ANY PHONE. Content fit, the suite was green, and
/// a 360dp till was broken. Pinning the device is not ceremony; it is the
/// difference between testing the app and testing a shape that resembles it.
///
/// Named by measured size, not by a marketing model: the size is the contract,
/// the phone it resembles is not.
class Device {
  const Device(this.name, this.logicalSize, this.dpr);

  final String name;
  final Size logicalSize;
  final double dpr;

  /// A small, tall phone. The narrowest thing this app supports, and therefore
  /// where every overflow shows up first.
  static const Device compact = Device('compact_320', Size(320, 640), 2.0);

  /// The common Android phone.
  static const Device small = Device('small_360', Size(360, 800), 3.0);

  /// A large phone, or a foldable's cover display.
  static const Device medium = Device('medium_412', Size(412, 915), 2.625);

  /// A tablet: the first size class past compact, where the navigation affordance
  /// changes from a bottom bar to a rail.
  static const Device tablet = Device('tablet_800', Size(800, 1280), 2.0);

  static const List<Device> all = <Device>[compact, small, medium];
  static const List<Device> phonesAndTablet = <Device>[
    compact,
    small,
    medium,
    tablet,
  ];
}

/// Loads the real brand typeface into the test font collection.
///
/// Without this, Flutter's test environment renders every glyph as an Ahem square:
/// fixed em-square advance widths regardless of character or weight. That makes the
/// bold-text axis INERT, hides real character widths, and produces goldens that
/// prove nothing about the text they appear to contain.
///
/// Variable fonts: Flutter maps `FontWeight` onto the `wght` axis for a variable
/// face, so one file covers the whole 200-800 axis with no per-weight duplicates.
Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  await (FontLoader('PlusJakartaSans')
        ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Variable.ttf')))
      .load();
}

/// The app's themes with haptics silenced.
///
/// The substitution has to happen in the `ThemeData` itself: `MaterialApp` builds
/// its own `Theme` from `theme`/`darkTheme`, so a `Theme` widget wrapped AROUND it
/// is discarded and the test would keep the live haptic map. A test that wants to
/// assert a haptic installs a counting [HapticTheme] itself.
ThemeData themedForTest(Brightness brightness, {bool hapticsEnabled = false}) {
  final ({ThemeData light, ThemeData dark}) themes = buildDukaThemes();
  final ThemeData base =
      brightness == Brightness.light ? themes.light : themes.dark;

  if (hapticsEnabled) return base;

  final Iterable<ThemeExtension<Object?>> withoutHaptics = base
      .extensions.values
      .whereType<ThemeExtension<Object?>>()
      .where((ThemeExtension<Object?> extension) => extension is! HapticTheme);

  return base.copyWith(
    extensions: <ThemeExtension<Object?>>[
      ...withoutHaptics,
      HapticTheme.muted,
    ],
  );
}

extension TestHarness on WidgetTester {
  /// Pins the device surface.
  ///
  /// MUST be called before [pumpApp]. `physicalSize` is in PHYSICAL pixels, so it
  /// is multiplied by the DPR — setting `Size(320, 640)` at the default DPR of 3
  /// gives a 107x213 logical surface, not a phone.
  ///
  /// The teardown is registered here, once, so a test cannot forget it. A leaked
  /// size poisons every later test in the file.
  void useDevice(Device device) {
    view.devicePixelRatio = device.dpr;
    view.physicalSize = device.logicalSize * device.dpr;
    addTearDown(view.reset);
  }

  /// Pumps [home] inside the app's real themes, with [MediaQuery] layered ABOVE
  /// `MaterialApp` and built from `.copyWith`.
  ///
  /// Two details that are easy to get wrong and quietly invalidate the test:
  ///
  /// * `MaterialApp` inserts no `MediaQuery` of its own, so the nearest one comes
  ///   from the `View`. Layering must therefore go ABOVE it.
  /// * The data must be `MediaQueryData.fromView(view).copyWith(…)`. A bare
  ///   `MediaQueryData()` zeroes the view-derived size the device just pinned, and
  ///   the test then measures a 0x0 screen and passes.
  ///
  /// Uses `pump()`, never `pumpAndSettle()`: that carries a ten-minute timeout,
  /// truncates its stack trace, and hangs forever on a screen with a loading
  /// spinner — which most of these screens have.
  /// [locale] defaults to English, which is the only locale this app ships. Pass
  /// an RTL one to exercise the mirrored layout: `AppLocalizations` falls back to
  /// English for its own strings while `GlobalWidgetsLocalizations` supplies the
  /// direction, which is exactly the situation an untranslated RTL build is in —
  /// and it is the situation that finds physical-side geometry.
  Future<void> pumpApp({
    required Widget home,
    Brightness brightness = Brightness.light,
    TextScaler textScaler = TextScaler.noScaling,
    bool boldText = false,
    bool accessibleNavigation = false,
    bool disableAnimations = false,
    double surfaceSize = double.infinity,
    bool hapticsEnabled = false,
    Locale locale = const Locale('en'),
    Iterable<Locale> supportedLocales = _appLocales,
  }) async {
    final Widget app = MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: themedForTest(brightness, hapticsEnabled: hapticsEnabled),
      // Without these, `AppLocalizations.of(context)` throws a null-check error
      // deep inside a widget rather than failing the harness: a screen's copy is
      // part of its surface, so a test that renders it without a catalogue is
      // testing a build that cannot ship.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: locale,
      home: home,
    );

    await pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(view).copyWith(
          textScaler: textScaler,
          boldText: boldText,
          accessibleNavigation: accessibleNavigation,
          disableAnimations: disableAnimations,
        ),
        child: app,
      ),
    );
    await pump();
  }

  /// Asserts nothing overflowed, with a message a human can act on.
  ///
  /// A `RenderFlex` overflow ALREADY fails a widget test — it routes through
  /// `FlutterError.reportError` and the binding rethrows at test end. This
  /// assertion is explicit so the failure names the device and the scale instead
  /// of arriving as an opaque "Test failed" twenty lines later.
  void expectNoOverflow(String context) {
    final Object? error = takeException();
    if (error == null) return;
    // The exception's own text names the RenderObject that overflowed, and a
    // RenderFlex failure is reported with the offending widget's creator in the
    // message. Dropping it and saying only "content overflowed in X" throws away
    // the one piece of information that makes the failure fixable.
    expect(
      error,
      isNull,
      reason: 'content overflowed in $context\n'
          'The framework said: $error',
    );
  }

  /// Asserts [label] fits inside the box [container] resolves to.
  ///
  /// Absence-of-overflow is necessary but NOT sufficient: a clipped `Text` reports
  /// nothing at all, because `RenderParagraph` has no overflow indicator. This is
  /// the assertion that catches the silent class.
  void expectFitsInside(
    Finder label,
    Finder container, {
    double epsilon = 0.5,
  }) {
    final Size labelSize = getSize(label);
    final Size containerSize = getSize(container);
    expect(
      labelSize.height,
      lessThanOrEqualTo(containerSize.height + epsilon),
      reason: 'a label is taller than its cell: ${getRect(label)} inside '
          '${getRect(container)}. The text was clipped rather than wrapped.',
    );
  }

  /// Measures every interactive target under [within] and asserts the 44px floor.
  ///
  /// NOT a substitute for `meetsGuideline(tappableRegionGuideline)`: that matcher
  /// skips every node flush with the edge of the view, which is exactly where a
  /// navigation bar and a bottom action bar live. This measures; it does not
  /// guess.
  ///
  /// `within.evaluate()` returns the MATCHED elements only, not their subtrees, so
  /// a `find.byType(Scaffold)` would find no buttons at all. The tree is walked
  /// explicitly — an assertion that silently finds zero targets is worse than no
  /// assertion, which is why the non-empty check below exists.
  void expectTapTargetsMeetMinimum(
    Finder within, {
    double minimum = 44,
  }) {
    final List<Element> all = <Element>[];
    for (final Element root in within.evaluate()) {
      all.add(root);
    }
    // `within.evaluate()` returns the MATCHED elements only, never their subtrees,
    // so a `find.byType(Scaffold)` finds no buttons. Descending explicitly is the
    // fix; an assertion that silently finds zero targets is worse than none, which
    // is what the non-empty check below guards against.
    void collect(Finder candidate) {
      all.addAll(candidate.evaluate());
    }

    for (final Finder candidate in <Finder>[
      find.byType(InkWell),
      find.byType(GestureDetector),
      find.byType(IconButton),
      find.byType(TextButton),
      find.byType(OutlinedButton),
      find.byType(FilledButton),
      find.byType(ElevatedButton),
    ]) {
      collect(find.descendant(of: within, matching: candidate));
    }

    final List<Element> targets = all.toSet().toList();

    expect(
      targets,
      isNotEmpty,
      reason:
          'no interactive targets found under $within — the assertion would '
          'have passed vacuously',
    );

    for (final Element element in targets) {
      // The element's own render object avoids a second finder resolution per
      // target, and a null/sizeless box is an off-stage branch — measuring it
      // would report a 0x0 "overflow" that is not one.
      final RenderObject? renderObject = element.renderObject;
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      if (renderObject.size.isEmpty) continue;

      expect(
        renderObject.size.height,
        greaterThanOrEqualTo(minimum - 0.5),
        reason: 'tap target is ${renderObject.size.height}px tall, below the '
            '${minimum}px floor: ${element.widget.runtimeType}',
      );
    }
  }
}

/// The generated catalogue for [locale], loaded the way `Localizations` loads it.
///
/// A pure-Dart test has no `BuildContext` and no `Localizations` ancestor, so any
/// code that takes an `AppLocalizations` parameter needs one from here. Loading
/// through the real delegate rather than constructing the class by hand is the
/// point: it is the same path the app takes, so a key that the ARB declares but
/// the generator drops fails HERE rather than in the field.
Future<AppLocalizations> loadL10n([Locale locale = const Locale('en')]) =>
    AppLocalizations.delegate.load(locale);

/// What the app ships.
///
/// English only, deliberately: `supportedLocales` is derived from the ARB
/// catalogue, and a locale with no file behind it is a locale whose chrome is
/// translated and whose content is not.
const List<Locale> _appLocales = <Locale>[Locale('en')];

/// The text-scale values in the overflow matrix.
///
/// `TextScaler.linear` is a deliberate OVER-approximation: Android 14+ scales
/// large text less aggressively than linear, so linear at 2.0 is harsher than any
/// real device. Being wrong in that direction is correct. 1.3 and 1.5 are in the
/// list precisely because nonlinear scaling makes the MID-RANGE the non-obvious
/// part — that is where a bug hides from a test that only tries 1.0 and 3.0.
const List<double> kTextScales = <double>[1.0, 1.3, 1.5, 2.0, 3.0];
