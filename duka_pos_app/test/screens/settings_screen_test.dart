// End-to-end render checks for Settings.
//
// Settings is the densest screen in the app: nine sections of switches, rows
// and buttons, each of which reflows in its own way at a large text scale. The
// question this test answers is whether the whole thing LAYS OUT — a section
// that clips at 2.0x on a 320dp phone is a control a shopkeeper cannot reach,
// and it is exactly the class of regression a unit test does not see.
//
// It renders `SettingsPanel` — the stateful screen splits its async work from
// its presentation precisely so this can be done from a constructed value
// instead of a database read in `initState`.
//
// `loadAppFonts` is not optional: under Ahem every glyph is a fixed em-square,
// so the x2.0 half of the matrix would pass vacuously.

import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/settings_screen.dart';
import 'package:duka_pos/services/inventory_importer.dart';
import 'package:duka_pos/ui/components/controls.dart';
import 'package:duka_pos/services/printer/printer_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// A panel with defaults, so each case overrides only what it is about.
Widget _panel({
  bool identityLinkPending = false,
  bool identityVerified = true,
  List<Staff> staff = const <Staff>[],
  PrinterConfig printer = const PrinterConfig(),
  bool mpesaEnabled = false,
  bool autoSyncEnabled = false,
  bool syncing = false,
  String? syncStatus,
  int vatRatePercent = 16,
  String tin = '',
  String tillCode = 'TILL-1',
}) =>
    SettingsPanel(
      // The handlers are inert: this suite asserts LAYOUT, not behaviour, and
      // the rules they encode are covered where the rule was written.
      onVerifyIdentity: () async {},
      onAddStaff: () async {},
      onResetPin: (_) {},
      onRemoveStaff: (_) async {},
      onToggleMpesa: (_) async {},
      onPairPrinter: () async {},
      onTestPrint: () async {},
      onSavePrinter: (_) async {},
      onOpenTaxSettings: () async {},
      onEditCreditSettings: () async {},
      onSetAutoSync: (_) async {},
      onSyncNow: () async {},
      onExportEncrypted: () async {},
      onRestoreEncrypted: () async {},
      onExport: () async {},
      onImport: () async {},
      importing: false,
      importProgress: ValueNotifier<ImportProgress?>(null),
      onEraseBackups: () async {},
      onDeleteAccount: () async {},
      accountDeleting: false,
      onAddShop: () async {},
      onManageShops: () async {},
      onOpenPortfolio: () {},
      onOpenActivity: () {},
      savingPaymentToggle: false,
      printerBusy: false,
      verifyingIdentity: false,
      identityLinkPending: identityLinkPending,
      identityVerified: identityVerified,
      staff: staff,
      printer: printer,
      mpesaEnabled: mpesaEnabled,
      autoSyncEnabled: autoSyncEnabled,
      syncing: syncing,
      syncStatus: syncStatus,
      vatRatePercent: vatRatePercent,
      tin: tin,
      tillCode: tillCode,
    );

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  group('settings screen', () {
    testWidgets('every section renders and nothing overflows', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel());

      tester.expectNoOverflow('settings at 1.0x on a small phone');

      // The sections, by the labels a shopkeeper reads. `SectionHeader`
      // renders them upper-cased, so that is what a finder has to look for.
      expect(
          find.text(l10n.settingsYourShopsTitle.toUpperCase()), findsOneWidget);
      expect(
          find.text(l10n.settingsStaffSection.toUpperCase()), findsOneWidget);
      expect(find.text(l10n.settingsPaymentMethodsSection.toUpperCase()),
          findsOneWidget);
      expect(find.text(l10n.settingsCreditSection.toUpperCase()), findsOneWidget);
      expect(
          find.text(l10n.settingsPrinterSection.toUpperCase()), findsOneWidget);
      expect(find.text(l10n.taxSettingsTitle.toUpperCase()), findsOneWidget);
      expect(find.text(l10n.settingsSyncSection.toUpperCase()), findsOneWidget);
      expect(
          find.text(l10n.settingsBackupSection.toUpperCase()), findsOneWidget);
      tester.expectNoOverflow('settings sections');
    });

    testWidgets('credit sales are visibly off by default and configurable',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel());

      expect(find.text(l10n.settingsCreditOffSummary), findsOneWidget);
      expect(find.text(l10n.settingsCreditSection.toUpperCase()), findsOneWidget);
      tester.expectNoOverflow('credit settings section');
    });

    testWidgets('the identity banner leads when the shop is unlinked',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(identityLinkPending: true),
      );

      // A banner, not a section: the one condition that is the shop's problem
      // rather than the phone's sits above everything else.
      expect(find.text(l10n.settingsIdentityNotLinkedTitle), findsOneWidget);
      // Asserted by its label, not by type: a printer section and a sync
      // section also carry a FilledButton, and counting types here would
      // silently start counting Mine.
      expect(find.widgetWithText(FilledButton, l10n.settingsVerifyAction),
          findsOneWidget);
      tester.expectNoOverflow('settings identity banner');
    });

    testWidgets('a staff roster lists rows and not the empty state',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(
          staff: <Staff>[
            Staff(name: 'Joseph', pinHash: 'y', role: 'cashier'),
            Staff(name: 'Brian', pinHash: 'z', role: 'manager'),
          ],
        ),
      );

      expect(find.text('Joseph'), findsOneWidget);
      expect(find.text('Brian'), findsOneWidget);
      expect(find.text(l10n.settingsStaffEmpty), findsNothing);
      tester.expectNoOverflow('settings staff rows');
    });

    testWidgets('an empty roster says so rather than looking broken',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel());

      expect(find.text(l10n.settingsStaffEmpty), findsOneWidget);
    });

    testWidgets('a paired printer shows its device and both switches',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(
          printer: PrinterConfig(
            macAddress: 'AA:BB:CC:DD:EE:FF',
            enabled: true,
          ),
        ),
      );

      expect(find.text('AA:BB:CC:DD:EE:FF'), findsOneWidget);
      // The 58mm roll, read from the config rather than a remembered default.
      expect(find.text(l10n.settingsPaperRoll(58)), findsOneWidget);
      // And the printing switch STATES that it is on. The switch's own position
      // says so, but a shop that has paired a printer and is wondering why no
      // paper came out is looking for a sentence, not for the direction a
      // toggle happens to be pointing.
      expect(find.text(l10n.settingsPrintingOnSubtitle), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(5));
      tester.expectNoOverflow('settings printer section');
    });

    testWidgets(
        'a paired printer that is switched off says so, and does not '
        'send the owner to pair another', (tester) async {
      // The regression this pins: the state used to be gated on
      // `PrinterConfig.isConfigured`, which requires `enabled` as well as an
      // address — so a till with a printer paired and printing switched off was
      // told to go and pair one. Two states, opposite responses, and only one of
      // them was ever reachable.
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(
          printer: PrinterConfig(
            macAddress: 'AA:BB:CC:DD:EE:FF',
            enabled: false,
          ),
        ),
      );

      expect(find.text(l10n.settingsPrintingPairedOffSubtitle), findsOneWidget);
      expect(find.text(l10n.settingsPrintingOnSubtitle), findsNothing);
      // And the printer is still named, so the owner knows it is the right one.
      expect(find.text('AA:BB:CC:DD:EE:FF'), findsOneWidget);
    });

    testWidgets('the tax summary names the rate, the TIN and the till',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(vatRatePercent: 16, tin: 'A123456789B', tillCode: 'KRA42'),
      );

      // `settingsTaxSummaryWithTin(rate, till, tin)` — the generated parameters
      // are ordered alphabetically (rate, till, tin), so the till code comes
      // SECOND and the TIN third. These were transposed, which printed the
      // TIN where the receipt till code belongs and vice versa.
      expect(
        find.text(l10n.settingsTaxSummaryWithTin(16, 'KRA42', 'A123456789B')),
        findsOneWidget,
      );
    });

    testWidgets('the sync status is announced, not just shown', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(syncStatus: l10n.settingsSyncSheets),
      );

      // A live region: a screen-reader user is told the sync landed instead of
      // having to find the line they cannot see.
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('auto-backup explains itself while the email is unverified',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(identityVerified: false),
      );

      // The screen is labels only, so the control's own state carries what a
      // paragraph under it used to say. A dead switch with no reason reads as
      // broken, so it must be findable and visibly inert.
      // The switch sits BESIDE its title in the row, not above it, so the
      // finder walks down into the row rather than up from the label.
      // `SettingsSwitchRow` is an `InkWell`, so the row is found through that
      // rather than through a `ListTile` it does not use.
      final Finder autoSyncRow = find.ancestor(
        of: find.text(l10n.settingsAutoBackupSync),
        matching: find.byType(InkWell),
      );
      final Finder autoSyncSwitch =
          find.descendant(of: autoSyncRow, matching: find.byType(Switch));
      expect(autoSyncSwitch, findsOneWidget);
      expect(tester.widget<Switch>(autoSyncSwitch).value, isFalse);
      // And it cannot be moved, which is the half that matters: a switch that
      // looks live while doing nothing is worse than one that reads as locked.
      expect(tester.widget<Switch>(autoSyncSwitch).onChanged, isNull);
      // Found through its own title rather than by position: M-Pesa and the
      // printer rows are switches too, and "the first switch" would go on
      // silently testing the wrong control.
      final Finder row = find.ancestor(
        of: find.text(l10n.settingsAutoBackupSync),
        matching: find.byType(SettingsSwitchRow),
      );
      final Switch autoBackup = tester.widget<Switch>(
        find.descendant(of: row, matching: find.byType(Switch)),
      );
      expect(autoBackup.value, isFalse);
      expect(autoBackup.onChanged, isNull);
      tester.expectNoOverflow('settings locked sync row');
    });

    testWidgets('auto-backup is live once the email is verified',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(identityVerified: true, autoSyncEnabled: true),
      );

      final Finder row = find.ancestor(
        of: find.text(l10n.settingsAutoBackupSync),
        matching: find.byType(SettingsSwitchRow),
      );
      final Switch autoBackup = tester.widget<Switch>(
        find.descendant(of: row, matching: find.byType(Switch)),
      );
      expect(autoBackup.value, isTrue);
      expect(autoBackup.onChanged, isNotNull);
    });

    testWidgets('fits at the largest text scale', (tester) async {
      tester.useDevice(Device.compact);
      await tester.pumpApp(
        home: _panel(
          staff: <Staff>[Staff(name: 'Joseph', pinHash: 'y', role: 'cashier')],
          printer: const PrinterConfig(macAddress: 'AA:BB:CC:DD:EE:FF'),
        ),
        textScaler: TextScaler.linear(2.0),
      );

      // Nothing may be clamped to achieve this: the brief bans
      // `withClampedTextScaling` and `FittedBox`, so the layout has to hold.
      tester.expectNoOverflow('settings at 2.0x on a 320dp phone');
    });

    testWidgets('renders in dark mode', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(),
        brightness: Brightness.dark,
      );

      tester.expectNoOverflow('settings in dark mode');
      expect(
          find.text(l10n.settingsYourShopsTitle.toUpperCase()), findsOneWidget);
    });

    testWidgets('every control clears the 44px floor', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(
          staff: <Staff>[Staff(name: 'Joseph', pinHash: 'y', role: 'cashier')],
          printer: const PrinterConfig(macAddress: 'AA:BB:CC:DD:EE:FF'),
        ),
      );

      // The rows are whole-row targets, so what must clear the floor is the row
      // and not just the switch's own box. The harness assertion walks the
      // subtree and fails on any target it finds that is too small.
      tester.expectTapTargetsMeetMinimum(
        find.byType(SettingsPanel),
        minimum: 44,
      );
    });
  });
}
