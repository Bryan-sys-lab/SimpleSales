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
      onSetAutoSync: (_) async {},
      onSyncNow: () async {},
      onExportEncrypted: () async {},
      onRestoreEncrypted: () async {},
      onExport: () async {},
      onImport: () async {},
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
      expect(
          find.text(l10n.settingsPrinterSection.toUpperCase()), findsOneWidget);
      expect(find.text(l10n.taxSettingsTitle.toUpperCase()), findsOneWidget);
      expect(find.text(l10n.settingsSyncSection.toUpperCase()), findsOneWidget);
      expect(
          find.text(l10n.settingsBackupSection.toUpperCase()), findsOneWidget);
      tester.expectNoOverflow('settings sections');
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
      expect(find.byType(Switch), findsNWidgets(4));
      tester.expectNoOverflow('settings printer section');
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

      // The switch is present and cannot move, and it says which step is
      // missing. A dead switch with no explanation is the one control on this
      // screen that reads as broken rather than as waiting.
      expect(find.text(l10n.settingsAutoBackupLockedSubtitle), findsOneWidget);
      expect(find.text(l10n.settingsAutoBackupSyncSubtitle), findsNothing);
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

      expect(find.text(l10n.settingsAutoBackupSyncSubtitle), findsOneWidget);
      expect(find.text(l10n.settingsAutoBackupLockedSubtitle), findsNothing);
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
