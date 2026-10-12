// End-to-end render checks for Tax settings.
//
// The screen reads four persisted settings from `initState`, which is the same
// problem the shift screen solved by splitting presentation from loading — so
// this suite renders `TaxSettingsPanel`, the value-driven widget the stateful
// screen delegates to, rather than seeding a database first. What it proves is
// that the three sections, the slider and the rows survive a small phone and the
// largest text scale, which is the regression a unit test cannot see.
//
// `loadAppFonts` is not optional: under Ahem every glyph is a fixed em-square,
// so the 2.0x half of this matrix would pass vacuously.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/screens/tax_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// A panel with defaults, so each case overrides only what it is about.
Widget _panel({
  bool loading = false,
  bool saving = false,
  bool isAdmin = true,
  int vatRatePercent = 16,
  bool pricesIncludeVat = true,
  String tillCode = 'KRA42',
  bool etimsEnabled = false,
  String tin = '',
  String etimsDeviceId = '',
  String? message,
  bool messageIsError = false,
}) =>
    TaxSettingsPanel(
      // Inert handlers: this suite asserts LAYOUT, and the rules the handlers
      // encode are covered where the rule was written.
      // `onPreviewVatRate` is the slider's local-only update, so it is inert
      // here too — this suite never drags the slider.
      onPreviewVatRate: (int _) {},
      onSaveVatRate: (int _) {},
      onSetPricesIncludeVat: (bool _) {},
      onEditTillCode: () {},
      onToggleEtims: (bool _) {},
      onEditTin: () {},
      onRefreshQueue: () {},
      loading: loading,
      saving: saving,
      isAdmin: isAdmin,
      vatRatePercent: vatRatePercent,
      pricesIncludeVat: pricesIncludeVat,
      tillCode: tillCode,
      etimsEnabled: etimsEnabled,
      tin: tin,
      etimsDeviceId: etimsDeviceId,
      message: message,
      messageIsError: messageIsError,
    );

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  group('tax settings panel', () {
    testWidgets('all three sections render and nothing overflows',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel());

      // `SectionHeader` renders them upper-cased, so that is what a finder
      // looks for.
      expect(
          find.text(l10n.taxSettingsVatSection.toUpperCase()), findsOneWidget);
      expect(find.text(l10n.taxSettingsReceiptNumberingSection.toUpperCase()),
          findsOneWidget);
      expect(find.text(l10n.taxSettingsEtimsSection.toUpperCase()),
          findsOneWidget);
      tester.expectNoOverflow('tax sections at 1.0x on a small phone');
    });

    testWidgets('the VAT worked example says what the rate does to a price',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel(vatRatePercent: 16));

      expect(
        find.text(TaxSettingsScreen.workedExample(l10n, 16)),
        findsOneWidget,
      );
      // The exempt wording, not the example, at zero.
      expect(find.text(l10n.taxSettingsVatExempt), findsNothing);
      tester.expectNoOverflow('tax worked example');
    });

    testWidgets('a zero rate is exempt, not a worked example of nothing',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel(vatRatePercent: 0));

      expect(find.text(l10n.taxSettingsVatExempt), findsOneWidget);
    });

    testWidgets('a till code names the numbering scheme KRA matches',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel(tillCode: 'KRA42'));

      expect(find.text(l10n.taxSettingsTillCodeHelp('KRA42')), findsOneWidget);
      // The verb, not a chevron: this row acts on the value rather than opening
      // a detail screen.
      expect(find.text(l10n.taxSettingsChangeAction), findsOneWidget);
    });

    testWidgets('a registered TIN shows the PIN rather than the prompt',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
          home: _panel(
              etimsEnabled: true,
              tin: 'A123456789B',
              etimsDeviceId: 'DEV0001'));

      expect(find.text(l10n.taxTaxpayerPIN('A123456789B')), findsOneWidget);
      expect(find.text(l10n.taxSettingsRegisteredDevice), findsOneWidget);
      expect(find.text('DEV0001'), findsOneWidget);
      expect(find.text(l10n.taxSettingsTinNotRegistered), findsNothing);
    });

    testWidgets('the result of an action is announced, not just shown',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel(message: l10n.taxSettingsSaved));

      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a non-admin is told, not shown an empty screen',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel(isAdmin: false));

      // Defence in depth in the widget, not only in the route.
      expect(find.text(l10n.taxSettingsAdminOnly), findsOneWidget);
      expect(find.text(l10n.taxSettingsVatSection.toUpperCase()), findsNothing);
    });

    testWidgets('loading is a skeleton shaped like the result', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel(loading: true));

      // Not a spinner: the skeleton says a list of sections is coming, and
      // nothing jumps when they arrive.
      expect(find.byType(TaxSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('fits at the largest text scale', (tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        home: _panel(
          etimsEnabled: true,
          tin: 'A123456789B',
          etimsDeviceId: 'DEV0001',
        ),
        textScaler: TextScaler.linear(2.0),
      );

      // Nothing may be clamped to achieve this: the brief bans
      // `withClampedTextScaling` and `FittedBox`, so the layout has to hold.
      tester.expectNoOverflow('tax panel at 2.0x on a 320dp phone');
    });

    testWidgets('renders in dark mode', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(),
        brightness: Brightness.dark,
      );

      tester.expectNoOverflow('tax panel in dark mode');
      expect(
          find.text(l10n.taxSettingsVatSection.toUpperCase()), findsOneWidget);
    });

    testWidgets('every control clears the 44px floor', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel(etimsEnabled: true));

      tester.expectTapTargetsMeetMinimum(
        find.byType(TaxSettingsPanel),
        minimum: 44,
      );
    });
  });
}
