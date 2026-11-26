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
import 'package:duka_pos/services/backend_service.dart';
import 'package:duka_pos/services/inventory_importer.dart';
import 'package:duka_pos/ui/components/controls.dart';
import 'package:duka_pos/ui/components/surface.dart';
import 'package:duka_pos/services/printer/printer_config.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void _noop() {}

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
  bool showDiagnostics = false,
  SubscriptionEntitlement? subscription,
  VoidCallback onOpenSubscription = _noop,
}) =>
    SettingsPanel(
      // The handlers are inert: this suite asserts LAYOUT, not behaviour, and
      // the rules they encode are covered where the rule was written.
      onVerifyIdentity: () async {},
      onAddStaff: () async {},
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
      subscription: subscription,
      onOpenSubscription: onOpenSubscription,
      onOpenDiagnostics: showDiagnostics ? _noop : null,
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
    testWidgets('hides diagnostics for staff sessions', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel());

      expect(find.text(l10n.diagnosticsTitle), findsNothing);
    });

    testWidgets('shows diagnostics when the owner session enables it',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel(showDiagnostics: true));

      expect(find.text(l10n.diagnosticsTitle), findsOneWidget);
    });

    testWidgets('every section renders and nothing overflows', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel());

      tester.expectNoOverflow('settings at 1.0x on a small phone');

      // The sections, by the labels a shopkeeper reads. `SectionHeader`
      // renders them in sentence case, so find them through SectionHeader.
      expect(
          find.descendant(
              of: find.byType(SectionHeader),
              matching: find.text(l10n.settingsYourShopsTitle)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(SectionHeader),
              matching: find.text(l10n.settingsStaffSection)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(SectionHeader),
              matching: find.text(l10n.settingsPaymentMethodsSection)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(SectionHeader),
              matching: find.text(l10n.settingsCreditSection)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(SectionHeader),
              matching: find.text(l10n.settingsPrinterSection)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(SectionHeader),
              matching: find.text(l10n.taxSettingsTitle)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(SectionHeader),
              matching: find.text(l10n.settingsSyncSection)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(SectionHeader),
              matching: find.text(l10n.settingsBackupSection)),
          findsOneWidget);
      tester.expectNoOverflow('settings sections');
    });

    testWidgets('shows the Admin-set subscription price and discount',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(
          subscription: const SubscriptionEntitlement(
            allowed: false,
            status: 'pending',
            priceMinor: 100000,
            discountPercent: 10,
            currency: 'KES',
            billingInterval: 'monthly',
          ),
        ),
      );

      expect(find.text(l10n.settingsSubscriptionSection), findsOneWidget);
      expect(
        find.textContaining(
            l10n.settingsSubscriptionPrice('KES', '1000.00', 'monthly')),
        findsOneWidget,
      );
      expect(
        find.textContaining(
            l10n.settingsSubscriptionAmountDue('KES', '900.00', 'monthly', 10)),
        findsOneWidget,
      );
      tester.expectNoOverflow('subscription plan settings');
    });

    testWidgets('uses the full quarterly server quote in subscription summary',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(
          subscription: const SubscriptionEntitlement(
            allowed: false,
            status: 'pending',
            priceMinor: 10000,
            discountPercent: 10,
            currency: 'KES',
            billingInterval: 'quarterly',
            checkout: SubscriptionCheckoutPreview(
              amountMinor: 22500,
              baseAmountMinor: 30000,
              discountAmountMinor: 7500,
              discountPercent: 25,
              durationMonths: 3,
            ),
          ),
        ),
      );

      expect(
        find.textContaining(
            l10n.settingsSubscriptionPrice('KES', '300.00', 'quarterly')),
        findsOneWidget,
      );
      expect(
        find.textContaining(l10n.settingsSubscriptionAmountDue(
            'KES', '225.00', 'quarterly', 25)),
        findsOneWidget,
      );
    });

    testWidgets('subscription settings row opens plan details', (tester) async {
      tester.useDevice(Device.small);
      var opened = false;
      await tester.pumpApp(
        home: _panel(onOpenSubscription: () => opened = true),
      );

      await tester.tap(find.text(l10n.settingsSubscriptionTitle));
      expect(opened, isTrue);
    });

    testWidgets('PayHero guide explains Till, Paybill, bank, and activation',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel());

      final Finder guide = find.byKey(
        const ValueKey<String>('payhero-setup-guide'),
      );
      await tester.scrollUntilVisible(
        guide,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(guide);
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsPayHeroTillGuide), findsOneWidget);
      expect(find.text(l10n.settingsPayHeroPaybillGuide), findsOneWidget);
      expect(find.text(l10n.settingsPayHeroBankGuide), findsOneWidget);
      expect(find.text(l10n.settingsPayHeroActivationGuide), findsOneWidget);
      expect(find.text(l10n.settingsPayHeroSubscriptionNote), findsOneWidget);
      tester.expectNoOverflow('expanded PayHero setup guide');
    });

    testWidgets('PayHero guide is translated in Swahili', (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel(), locale: const Locale('sw'));

      final AppLocalizations swahili =
          AppLocalizations.of(tester.element(find.byType(SettingsPanel)));
      final Finder guide = find.byKey(
        const ValueKey<String>('payhero-setup-guide'),
      );
      await tester.scrollUntilVisible(
        guide,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(guide);
      await tester.pumpAndSettle();

      expect(find.text(swahili.settingsPayHeroGuideTitle), findsOneWidget);
      expect(find.text(swahili.settingsPayHeroTillGuide), findsOneWidget);
      expect(find.text(swahili.settingsPayHeroPaybillGuide), findsOneWidget);
      expect(find.text(swahili.settingsPayHeroBankGuide), findsOneWidget);
      tester.expectNoOverflow('Swahili PayHero setup guide');
    });

    testWidgets('credit sales are visibly off by default and configurable',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(home: _panel());

      expect(find.text(l10n.settingsCreditOffSummary), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(SectionHeader),
              matching: find.text(l10n.settingsCreditSection)),
          findsOneWidget);
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

    testWidgets('staff rows preserve cashier, manager, and admin roles',
        (tester) async {
      tester.useDevice(Device.small);
      await tester.pumpApp(
        home: _panel(
          staff: <Staff>[
            Staff(name: 'Amina', pinHash: 'a', role: 'cashier'),
            Staff(name: 'Brian', pinHash: 'b', role: 'manager'),
            Staff(name: 'Caro', pinHash: 'c', role: 'ADMIN'),
          ],
        ),
      );

      expect(find.text(l10n.settingsRoleCashier), findsOneWidget);
      expect(find.text(l10n.settingsRoleManager), findsOneWidget);
      expect(
        find.text(l10n.settingsRoleAdminFull('Admin')),
        findsOneWidget,
      );
      tester.expectNoOverflow('settings staff role labels');
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
        find.ancestor(
          of: find.text(l10n.settingsSyncSheets),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
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
      expect(find.text(l10n.settingsYourShopsTitle), findsOneWidget);
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
