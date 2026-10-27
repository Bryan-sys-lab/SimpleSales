import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../profile/shop_profile.dart';
import '../profile/profile_navigation.dart';
import '../profile/profile_terminology.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/money.dart';
import '../utils/datetime_format.dart';
import '../models/audit_log.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/account_deletion_service.dart';
import '../services/audit_actor.dart';
import '../services/auth_service.dart';
import '../services/session_refresh_mixin.dart';
import '../services/staff_credential_cache.dart';
import '../services/sync_service.dart';
import '../services/app_busy.dart';
import '../services/excel_service.dart';
import '../services/inventory_importer.dart';
import '../services/import_row_parser.dart';
import '../routing/routes.dart';
import '../services/roles.dart';
import '../app_brand.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/backend_service.dart';
import '../services/auto_sync_service.dart';
import '../services/encrypted_backup_service.dart';
import '../ui/brand/nerva_wordmark.dart';
import '../ui/components/operation_result.dart';
import '../services/workspace_service.dart';
import '../services/printer/printer_config.dart';
import '../services/printer/printer_service.dart';
import '../services/printer/receipt_builder.dart';
import '../services/printer/esc_pos_printer.dart';
import '../services/printer/esc_pos_encoder.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/screen_title.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../ui/dialogs/verify_identity_dialog.dart';
import '../ui/layout/page.dart';
import '../services/app_update_service.dart';
import '../services/app_release.dart';
import '../services/pin_reset_service.dart';
import '../utils/pin_rules.dart';
import 'blackbee_seed_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// What the "add a shop on this device" dialog handed back.
///
/// A value rather than two loose strings, because the two always travel
/// together and it is not possible to have one without the other: a shop
/// without a PIN has no way in, and a PIN without a shop has nothing to open.
class _NewShopDetails {
  const _NewShopDetails(
      {required this.name, required this.pin, required this.profile});

  /// The shop's name, as typed.
  final String name;

  /// The PIN that opens THIS shop.
  final String pin;
  final ShopProfile profile;
}

/// The PayHero channel details the owner needs to recognise the destination
/// without putting PayHero credentials on the till.
class _MpesaChannelDetails {
  const _MpesaChannelDetails({
    required this.channelType,
    required this.merchantNumber,
  });

  final String channelType;
  final String merchantNumber;
}

class _SettingsScreenState extends State<SettingsScreen>
    with SessionRefresh<SettingsScreen> {
  final _sync = SyncService();
  final _excel = ExcelService();
  List<Staff> _staff = [];

  /// Whether an import is running.
  ///
  /// The button is disabled while it is: an import that is started twice runs
  /// twice, and the owner has no way to tell that from an import that is
  /// simply slow.
  bool _importing = false;

  /// Where the import has got to, for the bar.
  ///
  /// A notifier, not a field: the settings screen is a big tree, and a
  /// progress step that rebuilt all of it a hundred times would be the jank
  /// the progress bar was meant to prevent. Only the bar listens.
  final ValueNotifier<ImportProgress?> _importProgress =
      ValueNotifier<ImportProgress?>(null);
  bool _syncing = false;
  String? _syncStatus;
  bool _verifyingIdentity = false;
  bool _mpesaEnabled = false;
  int? _mpesaChannelId;
  String _mpesaChannelType = 'Till';
  String _mpesaMerchantNumber = '';
  bool _backendLinked = false;
  bool _automaticBackupSync = false;
  bool _savingToggle = false;
  PrinterConfig _printer = const PrinterConfig();
  int _vatRatePercent = kDefaultVatRatePercent;
  String _tillCode = '';
  String _tin = '';
  bool _creditEnabled = false;
  int _creditDefaultLimitMinor = 0;
  int _expenseApprovalLimitMinor = 500000;
  String _creditLimitMode = 'block';
  bool _creditCashiersAllowed = false;
  String _creditReminderTemplate = '';
  bool _discountsEnabled = false;
  int _cashierDiscountPercent = 0;
  int _managerDiscountPercent = 0;
  bool _discountReasonRequired = false;
  bool _discountBelowCostAllowed = false;
  bool _cashDrawerEnabled = false;
  bool _cashDrawerOnCashSale = false;
  int _cashDrawerPin = 0;
  int _cashDrawerOnMs = 50;
  int _cashDrawerOffMs = 500;

  int _printerBusyCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void clearForSession() {
    _staff = const <Staff>[];
  }

  @override
  Future<void> reloadFromSession() => _load();

  Future<void> _load() async {
    final staff = await DatabaseHelper.instance.getStaff();
    final prefs = await SharedPreferences.getInstance();
    final db = DatabaseHelper.instance;
    final printer = await PrinterConfig.load();
    final tillCode = await db.getTillCode();
    final vatRate = await db.getVatRatePercent();
    final tin = (await db.getSetting(DatabaseHelper.settingTin)) ?? '';
    final creditEnabled = await db.getCreditEnabled();
    final creditLimit = await db.getCreditDefaultLimit();
    final creditMode = await db.getCreditLimitMode();
    final creditCashiers = await db.getCreditCashiersAllowed();
    final creditTemplate = await db.getCreditReminderTemplate();
    final expenseApprovalLimit = await db.getExpenseApprovalLimitMinor();
    final discountsEnabled = await db.getDiscountsEnabled();
    final cashierDiscountPercent = await db
        .getDiscountPercent(DatabaseHelper.settingCashierDiscountPercent);
    final managerDiscountPercent = await db
        .getDiscountPercent(DatabaseHelper.settingManagerDiscountPercent);
    final discountReasonRequired = await db.getDiscountReasonRequired();
    final discountBelowCostAllowed = await db.getDiscountBelowCostAllowed();
    final cashDrawerEnabled =
        await db.getSetting(DatabaseHelper.settingCashDrawerEnabled) == '1';
    final cashDrawerOnCashSale =
        await db.getSetting(DatabaseHelper.settingCashDrawerOnCashSale) == '1';
    final cashDrawerPin = int.tryParse(
          await db.getSetting(DatabaseHelper.settingCashDrawerPin) ?? '',
        ) ??
        0;
    final cashDrawerOnMs = int.tryParse(
          await db.getSetting(DatabaseHelper.settingCashDrawerOnMs) ?? '',
        ) ??
        50;
    final cashDrawerOffMs = int.tryParse(
          await db.getSetting(DatabaseHelper.settingCashDrawerOffMs) ?? '',
        ) ??
        500;
    final mpesaChannelId = int.tryParse(
      (await db.getSetting(DatabaseHelper.settingMpesaChannelId) ?? '').trim(),
    );
    final mpesaChannelType =
        (await db.getSetting(DatabaseHelper.settingMpesaChannelType))?.trim();
    final mpesaMerchantNumber =
        (await db.getSetting(DatabaseHelper.settingMpesaMerchantNumber))
            ?.trim();
    final automaticBackupSync = await AutoSyncService.enabled;
    if (!mounted) return;
    setState(() {
      _staff = staff;
      _mpesaEnabled = prefs.getBool('mpesa_enabled_local') ?? false;
      _mpesaChannelId = mpesaChannelId;
      _mpesaChannelType = mpesaChannelType == 'Paybill' ? 'Paybill' : 'Till';
      _mpesaMerchantNumber = mpesaMerchantNumber ?? '';
      _automaticBackupSync = automaticBackupSync;
      _printer = printer;
      _tillCode = tillCode;
      _vatRatePercent = vatRate;
      _tin = tin;
      _creditEnabled = creditEnabled;
      _creditDefaultLimitMinor = creditLimit;
      _expenseApprovalLimitMinor = expenseApprovalLimit;
      _creditLimitMode = creditMode;
      _creditCashiersAllowed = creditCashiers;
      _creditReminderTemplate = creditTemplate;
      _discountsEnabled = discountsEnabled;
      _cashierDiscountPercent = cashierDiscountPercent;
      _managerDiscountPercent = managerDiscountPercent;
      _discountReasonRequired = discountReasonRequired;
      _discountBelowCostAllowed = discountBelowCostAllowed;
      _cashDrawerEnabled = cashDrawerEnabled;
      _cashDrawerOnCashSale = cashDrawerOnCashSale;
      _cashDrawerPin = cashDrawerPin;
      _cashDrawerOnMs = cashDrawerOnMs;
      _cashDrawerOffMs = cashDrawerOffMs;
    });
    _backendLinked = await BackendService.isBackendLinked;
    if (!mounted) return;
    setState(() {});
  }

  bool get _printerBusy => _printerBusyCount > 0;

  void _setPrinterBusy(bool value) {
    if (!mounted) return;
    setState(() {
      _printerBusyCount = value ? _printerBusyCount + 1 : _printerBusyCount - 1;
      if (_printerBusyCount < 0) _printerBusyCount = 0;
    });
  }

  static String _printerMessage(
    AppLocalizations l10n,
    PrinterFailure failure,
  ) =>
      switch (failure) {
        PrinterFailure.permissionDenied =>
          l10n.settingsPrinterPermissionNeeded(SimplePosBrand.appName),
        PrinterFailure.permissionPermanentlyDenied =>
          l10n.settingsPrinterPermissionDenied(SimplePosBrand.appName),
        PrinterFailure.notPaired => l10n.settingsPrinterNotPaired,
        PrinterFailure.unavailable => l10n.settingsPrinterUnavailable,
        PrinterFailure.connectFailed => l10n.settingsPrinterUnreachable,
        PrinterFailure.printFailed => l10n.settingsPrinterConnectionDropped,
        PrinterFailure.disabled => l10n.settingsPrinterDisabled,
      };

  Future<void> _chooseAndPairPrinter() async {
    // Read before the first await: pairing opens system dialogs and this screen
    // can be left behind by all of them.
    final l10n = AppLocalizations.of(context);
    final printer = EscPosPrinter();
    _setPrinterBusy(true);
    try {
      if (!await printer.isAvailable()) {
        // Not "no printers found" — the radio itself is unusable. Saying so
        // saves the owner scanning a list that cannot ever be populated.
        if (!await printer.hasPermission()) {
          final granted = await printer.requestPermission();
          if (!granted) {
            final permanently = await printer.isPermissionPermanentlyDenied();
            _err(_printerMessage(
              l10n,
              permanently
                  ? PrinterFailure.permissionPermanentlyDenied
                  : PrinterFailure.permissionDenied,
            ));
            return;
          }
        }
        if (!await printer.isAvailable()) {
          _err(_printerMessage(l10n, PrinterFailure.unavailable));
          return;
        }
      }

      // The printer is chosen through a dialog that can RE-SCAN.
      //
      // The list used to be fetched once, before the dialog was built, and the
      // dialog was static. A shop that powered the printer on after tapping
      // "Pair a printer" saw "no printers" with no way to look again — the
      // usual reason a thermal printer is not visible is that it has not been
      // discovered yet, and the only remedy is another scan.
      // The navigator and the snapshot are both captured BEFORE the await:
      // the context must not cross the gap, and a dialog shown from a stale
      // context is the classic way this crashes after a rebuild.
      final String selectedAddress = _printer.macAddress;
      // `mounted` here is the guard the lint asks for: this runs inside an
      // async method that already awaited the Bluetooth permission check, and
      // a context used after that must be re-confirmed.
      if (!mounted) return;
      final chosen = await showDialog<PrinterDevice>(
        context: context,
        builder: (BuildContext dialogContext) => _PrinterChooser(
          printer: printer,
          selectedAddress: selectedAddress,
        ),
      );
      if (chosen == null) return;
      if (!mounted) return;

      final paired = await printer.pair(chosen.address);
      if (!mounted) return;
      if (!paired && !await printer.isPaired(chosen.address)) {
        _err(l10n.settingsPairingCancelled);
        return;
      }

      await _savePrinter(_printer.copyWith(
        macAddress: chosen.address,
        // Turning the shop on here rather than making the owner find a second
        // switch: a printer they just paired is a printer they want used.
        enabled: true,
        // And the same reasoning one switch over. A shop pairs a printer to
        // print receipts, so leaving print-after-sale off after pairing means
        // the receipt they just wired up never appears on a sale — the switch
        // exists to turn it OFF, not as a second thing to discover.
        printAfterSale: true,
      ));
      if (!mounted) return;
      _err(l10n.settingsPrinterPaired(chosen.label));
    } on PrinterException catch (error) {
      _err(_printerMessage(AppLocalizations.of(context), error.failure));
    } finally {
      _setPrinterBusy(false);
    }
  }

  Future<void> _testPrint() async {
    if (!_printer.isConfigured) {
      _err(AppLocalizations.of(context).settingsPairAPrinterFirst);
      return;
    }
    final state = context.read<AppState>();
    _setPrinterBusy(true);
    try {
      final now = DateTime.now();
      final items = [
        SaleItem(
          saleId: 0,
          productId: 0,
          productName: 'Test item',
          qty: 2,
          unitPrice: Money.fromMajor(50),
          unitCost: Money.fromMajor(20),
        ),
      ];
      final receipt = ReceiptInput(
        shopName: state.owner?.shopName ?? 'Duka POS',
        receiptNumber: 'TEST-000000',
        issuedAt: now,
        cashierName: 'Printer test',
        cashierRole: 'Test',
        items: items,
        total: Money.fromMajor(100),
        amountTendered: Money.fromMajor(100),
        changeGiven: Money.zero,
        pricesIncludeVat: true,
      );
      // The SAME budget for the layout and the encode, taken from the printer
      // the shop is actually configured for.
      //
      // This used to lay the slip out against a hardcoded `k58mmColumnBudget`
      // while encoding against `_printer.paperWidth.columnBudget`. Those are the
      // only two numbers involved, so the split was invisible — but the budget
      // decides the shop name's magnification and its centring, so an 80mm shop
      // printed its test slip with the name single-width and centred in 32
      // columns while every real receipt had it double-width in 48. A test
      // print that does not match the receipt it claims to test is worse than
      // no test print: it looks like verification.
      final budget = _printer.paperWidth.columnBudget;
      final bytes = const EscPosEncoder().encode(
        ReceiptBuilder(columnBudget: budget).build(receipt),
        columnBudget: budget,
      );
      final printer = EscPosPrinter();
      await printer.connect(_printer.macAddress);
      await printer.send(bytes);
      if (!mounted) return;
      _err(AppLocalizations.of(context).settingsTestReceiptSent);
    } on PrinterException catch (error) {
      _err(_printerMessage(AppLocalizations.of(context), error.failure));
    } finally {
      _setPrinterBusy(false);
    }
  }

  Future<void> _savePrinter(PrinterConfig config) async {
    // Read before the await: the config write is the async gap.
    final AppState state = context.read<AppState>();
    await config.save();
    // The printer config is the setup a shop changes once and then trusts for
    // years, so when a receipt stops printing there is exactly one place to
    // look for who last changed it.
    await recordActionAudit(
      state,
      action: AuditAction.printerSaved,
      entity: AuditEntity.settings,
      detail: config.isConfigured && config.enabled
          ? '${config.macAddress}, printing on'
          : 'printing off',
    );
    if (!mounted) return;
    setState(() => _printer = config);
  }

  /// Opens the dedicated tax screen.
  Future<void> _openTaxSettings() async {
    if (!context.read<AppState>().isAdmin) {
      _err(AppLocalizations.of(context).taxSettingsAdminOnly);
      return;
    }
    if (!mounted) return;
    // `push`, not `go`: tax settings is a sheet you come back FROM, and `go`
    // would replace the branch and lose the Settings scroll position behind it.
    await context.push(Routes.taxSettings);
    if (!mounted) return;
    // The screen can change the rate, the till code and the TIN; Settings shows
    // all three in its summary line, so re-read rather than guess.
    await _load();
  }

  Future<void> _editCreditSettings() async {
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreditSettingsSheet(
        enabled: _creditEnabled,
        defaultLimitMinor: _creditDefaultLimitMinor,
        limitMode: _creditLimitMode,
        cashiersAllowed: _creditCashiersAllowed,
        reminderTemplate: _creditReminderTemplate,
      ),
    );
    if (result == null || !mounted) return;
    final int? limit = result['defaultLimitMinor'] as int?;
    if (limit == null) return;
    final AppState state = context.read<AppState>();
    await DatabaseHelper.instance.setCreditEnabled(result['enabled'] as bool);
    await DatabaseHelper.instance.setCreditDefaultLimit(limit);
    await DatabaseHelper.instance
        .setCreditLimitMode(result['limitMode'] as String);
    await DatabaseHelper.instance
        .setCreditCashiersAllowed(result['cashiersAllowed'] as bool);
    await DatabaseHelper.instance
        .setCreditReminderTemplate(result['reminderTemplate'] as String);
    await recordActionAudit(
      state,
      action: AuditAction.paymentMethodChanged,
      entity: AuditEntity.settings,
      detail: 'credit ${result['enabled'] == true ? 'on' : 'off'}, limit '
          '${formatMoney(Money.fromMinor(limit))}, over-limit ${result['limitMode']}',
    );
    if (!mounted) return;
    _err(AppLocalizations.of(context).settingsCreditSaved);
    await _load();
  }

  Future<void> _editExpenseApprovalLimit() async {
    final controller = TextEditingController(
      text: Money.fromMinor(_expenseApprovalLimitMinor)
          .asMajor
          .toStringAsFixed(0),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cashier payout approval limit'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount (KSh)'),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value < 0 || !mounted) return;
    await DatabaseHelper.instance.setExpenseApprovalLimitMinor(
      Money.fromMajor(value).minorUnits,
    );
    await _load();
  }

  Future<void> _editDiscountSettings() async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discounts and price overrides'),
        content: _DiscountSettingsForm(
          enabled: _discountsEnabled,
          cashierPercent: _cashierDiscountPercent,
          managerPercent: _managerDiscountPercent,
          reasonRequired: _discountReasonRequired,
          belowCostAllowed: _discountBelowCostAllowed,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final db = DatabaseHelper.instance;
    await db.setSetting(DatabaseHelper.settingDiscountsEnabled,
        result['enabled'] == true ? '1' : '0');
    await db.setSetting(DatabaseHelper.settingCashierDiscountPercent,
        '${result['cashierPercent']}');
    await db.setSetting(DatabaseHelper.settingManagerDiscountPercent,
        '${result['managerPercent']}');
    await db.setSetting(DatabaseHelper.settingDiscountReasonRequired,
        result['reasonRequired'] == true ? '1' : '0');
    await db.setSetting(DatabaseHelper.settingDiscountBelowCostAllowed,
        result['belowCostAllowed'] == true ? '1' : '0');
    await _load();
  }

  void _err(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// True while the deletion is running, so the row can be disabled and the
  /// screen can say so rather than looking ignored.
  bool _deletingAccount = false;

  /// Deletes the online account and renders what it held unreadable.
  ///
  /// Gated on the admin PIN the same way every other destructive action in
  /// this screen is, so a till left unlocked on a counter cannot be wiped by
  /// someone passing by. The confirmation text names what is lost, because
  /// "are you sure" over an action like this tells the owner nothing they need.
  Future<void> _deleteOnlineAccount() async {
    final AppState state = context.read<AppState>();
    final l10n = AppLocalizations.of(context);

    // 1. The admin PIN, verified against the local hash, with the till-wide
    //    lockout shared with the login pad so this dialog is not a way around
    //    the attempt counting.
    final String? pin = await showVerifyPinSheet(
      context,
      email: PinResetService.maskEmail(state.owner?.email ?? ''),
      onSubmit: (String entered) =>
          _verifyOwnerPinOrError(entered, state.owner?.pinHash ?? '', l10n),
    );
    if (pin == null || !mounted) return;

    // 2. The confirmation, which has to be explicit about irreversibility.
    //    This is the only screen in the app where the honest advice is "if you
    //    are not certain, cancel" rather than a reassurance.
    //
    //    The SHARED dialog, not a hand-rolled one: a hand-rolled dialog is
    //    where the wrong navigator gets popped, and a dismissal is its own
    //    outcome rather than a silent "yes".
    final ConfirmOutcome outcome = await confirmIrreversible(
      context,
      title: l10n.accountDeleteConfirmTitle,
      message: l10n.accountDeleteConfirmMessage,
      confirmLabel: l10n.accountDeleteConfirmAction,
      cancelLabel: l10n.actionCancel,
    );
    if (outcome is! ConfirmAccepted || !mounted) return;

    // 3. The LOCAL accounts, asked about separately.
    //
    //    The erasure seals the cashiers' sign-in details, which makes them
    //    unusable. It does not remove the rows, and a row that says "there was
    //    a cashier here" is a fact the owner asked to have erased. So the
    //    owner is asked, once, in words, and the answer decides whether the
    //    rows go.
    //
    //    The question is separate because the two promises are different: a
    //    till whose cashiers can still sign in is a till somebody else can
    //    use. Deleting the account and keeping the logins is a legitimate
    //    choice — it is what an owner does when they are handing the till to
    //    someone else — and it is not one to be made by omission.
    final bool deleteLocalAccounts = await _confirmLocalAccountDeletion();
    if (!mounted) return;

    setState(() => _deletingAccount = true);
    try {
      final report = await AccountDeletionService.deleteAccount(
        pin: pin,
        deleteLocalAccounts: deleteLocalAccounts,
      );
      if (!mounted) return;
      // The receipt is offered for keeping, because the owner will need to show
      // someone that the account is gone.
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(l10n.accountDeleteDoneTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(report.remoteDeleted
                    ? l10n.accountDeleteDoneRemote
                    : l10n.accountDeleteDoneLocalOnly),
                SizedBox(height: AppSpacing.of(context).sm),
                // What happened to the cashier logins on this phone, said
                // plainly: either they are gone, or they are sealed and still
                // there, and the owner needs to know which.
                Text(
                  report.localAccountsDeleted
                      ? l10n.accountDeleteLocalAccountsRemoved
                      : l10n.accountDeleteLocalAccountsSealed,
                  style: AppTypography.of(context).bodySmall,
                ),
                SizedBox(height: AppSpacing.of(context).md),
                Text(
                  l10n.accountDeleteReceipt(
                    report.deletionId,
                    formatInstant(report.completedAt.toIso8601String()),
                  ),
                  style: AppTypography.of(context).bodySmall,
                ),
                // A failed compaction is the one partial-erasure state worth
                // naming: the data is unreadable but the file was never fully
                // rewritten, and only the owner can act on that.
                if (!report.compacted) ...<Widget>[
                  SizedBox(height: AppSpacing.of(context).sm),
                  Text(
                    l10n.accountDeleteCompactionPending,
                    style: AppTypography.of(context).bodySmall?.copyWith(
                          color: AppColors.of(context).danger,
                        ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            FilledButton(
              // The DIALOG's own context. `showDialog` pushes onto the root
              // navigator, so popping with the screen's context closed the
              // screen behind the receipt instead of the receipt itself.
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.actionDone),
            ),
          ],
        ),
      );
    } on AccountDeletionException catch (e) {
      if (!mounted) return;
      // The lockout remaining is read HERE rather than stashed earlier, because
      // it is the one message whose value is still moving while the dialog is
      // open — and a countdown read a minute ago would be a minute wrong.
      final int lockedSeconds =
          (await AuthService.tillLockoutRemaining())?.inSeconds ?? 0;
      _err(switch (e.reason) {
        AccountDeletionFailure.lockedOut =>
          l10n.settingsVerifyPinLocked(lockedSeconds),
        AccountDeletionFailure.localErasureFailed =>
          l10n.accountDeleteErasureFailed,
        AccountDeletionFailure.wrongPin => l10n.settingsVerifyPinWrong,
      });
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  /// Asks whether the cashier logins on this phone should be deleted too.
  ///
  /// Returns true to delete them. The destructive answer is the one on the
  /// filled button, because the owner has come here to delete their account
  /// and a till that still accepts a cashier's PIN is not a deleted till.
  ///
  /// Cancelled is treated as "keep them": a dialog dismissed is a question
  /// that was not answered, and the answer that changes least is the safe
  /// one for the data.
  Future<bool> _confirmLocalAccountDeletion() async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.accountDeleteLocalAccountsTitle),
        content: Text(l10n.accountDeleteLocalAccountsMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.accountDeleteLocalAccountsKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.of(context).danger,
            ),
            child: Text(l10n.accountDeleteLocalAccountsDelete),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// The owner PIN, checked against the local hash with the till-wide lockout
  /// honoured. Returns null when it is right, or the message to show.
  ///
  /// ONE implementation, because this precheck is security-relevant and was
  /// written out three times — here for verify-identity, again for the
  /// delete-account flow, and a third time inside
  /// [AccountDeletionService.deleteAccount]. Any change to how a wrong PIN is
  /// counted would have had to be mirrored in all three or the flows would
  /// silently disagree about how hard it is to guess a PIN.
  ///
  /// The lockout it shares with the login pad is the point of the whole thing:
  /// without an attempt counter on this path, a dialog on an unattended till is
  /// a PIN oracle. 10,000 four-digit values is minutes of guessing.
  static Future<String?> _verifyOwnerPinOrError(
      String entered, String expectedHash, AppLocalizations l10n) async {
    if (await AuthService.isTillLockedOut()) {
      final Duration? remaining = await AuthService.tillLockoutRemaining();
      return l10n.settingsVerifyPinLocked(remaining?.inSeconds ?? 0);
    }
    if (!await AuthService.verifyPin(entered, expectedHash)) {
      // Counted against the owner's key and against the till as a whole, so
      // switching identities does not reset the budget.
      await AuthService.recordFailure(AuthService.ownerLockoutKey);
      return l10n.settingsVerifyPinWrong;
    }
    return null;
  }

  Future<void> _eraseEncryptedBackups() async {
    // Read before the dialog's async gap.
    final AppState state = context.read<AppState>();
    // Read ONCE, before the dialog's async gap. A `BuildContext` does not
    // survive an await, and reading it afterwards is how a screen ends up
    // building a string in a language that is no longer the one on the device.
    final l10n = AppLocalizations.of(context);
    // The SHARED dialog. This one used to pop the SETTINGS branch instead of
    // the dialog, which closed the whole screen behind it.
    final ConfirmOutcome outcome = await confirmIrreversible(
      context,
      title: l10n.settingsEraseBackupsTitle,
      message: l10n.settingsEraseBackupsMessage,
      confirmLabel: l10n.settingsEraseBackupsConfirm,
      cancelLabel: l10n.actionCancel,
    );
    if (outcome is! ConfirmAccepted) return;
    final BackupErasureResult result =
        await EncryptedBackupService.cryptographicEraseLocalBackups();
    if (!mounted) return;
    // The outcome, in a number the owner can check — and NOT through the
    // error helper, because a successful erasure is not an error.
    //
    // "The backups are erased" is a claim nobody can check. "Three backup
    // files were erased" is a claim they can, and on a till the whole point
    // of pressing the button is to be sure.
    // The outcome, on a screen: this is the most destructive action in the
    // app, and "the backups are erased" in a snackbar that vanishes in four
    // seconds is not a receipt.
    if (result.complete) {
      showOperationSuccess(
        context,
        title: l10n.settingsBackupsErasedTitle,
        message: l10n.settingsBackupsErasedCount(result.filesErased),
        detailIcon: Icons.backup_outlined,
      );
    } else {
      showOperationFailure(
        context,
        title: l10n.settingsBackupsEraseFailedTitle,
        message: l10n.settingsBackupsEraseFailed,
        icon: Icons.backup_outlined,
      );
    }
    // The single most destructive action in the app, and the one an exclusion
    // the log exists for: after this, the device holds no restorable backup.
    await recordActionAudit(
      state,
      action: AuditAction.backupErased,
      entity: AuditEntity.backup,
      detail: 'local encrypted backups erased',
    );
  }

  Future<void> _addStaff() async {
    // Read once, before the dialog. A `showDialog` is an async gap, and the
    // screen can be popped underneath it — a lookup after the await would be
    // reading a scope whose element is gone.
    final l10n = AppLocalizations.of(context);
    // Read before the dialog's async gap.
    final state = context.read<AppState>();
    final result = await showDialog<Map<String, String>>(
        context: context, builder: (_) => const _StaffDialog());
    if (result == null) return;
    final name = (result['name'] ?? '').trim();
    if (name.isEmpty) {
      _err(l10n.settingsEnterStaffName);
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(result['pin'] ?? '')) {
      _err('PIN must be exactly 4 digits');
      return;
    }
    if (_staff.any((s) => s.name.toLowerCase() == name.toLowerCase())) {
      _err(l10n.settingsStaffNameTaken(name));
      return;
    }
    try {
      await DatabaseHelper.instance.addStaff(Staff(
          name: name,
          role: result['role'] ?? 'cashier',
          pinHash: await AuthService.hashPin(result['pin']!)));
      // Logged after the row exists, and carrying the role: "a cashier was
      // added" and "a manager was added" are different facts.
      await recordActionAudit(
        state,
        action: AuditAction.staffAdded,
        entity: AuditEntity.staff,
        entityId: name,
        detail: result['role'] ?? 'cashier',
      );
      if (_backendLinked) {
        try {
          await BackendService.syncStaffToBackend();
        } catch (_) {
          if (!mounted) return;
          // Saved here, not on the server yet. Said plainly, because a till
          // that shows the same message for a success and a partial success
          // cannot be trusted with either.
          showOperationSuccess(
            context,
            title: l10n.settingsStaffSavedTitle,
            message: l10n.settingsStaffSavedOffline,
            detailIcon: Icons.cloud_off_outlined,
          );
        }
      }
      await _load();
      if (!mounted) return;
      showOperationSuccess(
        context,
        title: l10n.settingsStaffSavedTitle,
        message: name,
        detailIcon: Icons.person_add_outlined,
      );
    } catch (e) {
      if (!mounted) return;
      showOperationFailure(
        context,
        title: l10n.settingsStaffSaveFailedTitle,
        message: l10n.settingsAddStaffFailed,
      );
    }
  }

  Future<void> _resetPin(Staff s) async {
    final l10n = AppLocalizations.of(context);
    final state = context.read<AppState>();
    final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => _StaffDialog(existingName: s.name, pinOnly: true));
    if (result == null) return;
    if (!RegExp(r'^\d{4}$').hasMatch(result['pin'] ?? '')) {
      _err(l10n.validationPinNotFourDigits);
      return;
    }
    try {
      await DatabaseHelper.instance
          .resetStaffPin(s.id!, await AuthService.hashPin(result['pin']!));
      // The cached offline credential goes with it. The cache holds a hash of
      // the OLD pin, and the till falls back to it when the backend is
      // unreachable — so without this the cashier who just had their PIN
      // changed keeps signing in with the old one until the next online
      // sign-in overwrites the cache.
      await StaffCredentialCache.clearStaffCredentials(s.id!);
      if (!mounted) return;
      showOperationSuccess(
        context,
        title: l10n.settingsPinResetTitle,
        message: l10n.settingsPinResetFor(s.name),
        detailIcon: Icons.pin_outlined,
      );
      if (!mounted) return;
      // A reset is how a locked-out cashier gets back in, so a PIN changed at
      // 11pm by someone who is not the named cashier is worth having recorded.
      await recordActionAudit(
        state,
        action: AuditAction.staffPinReset,
        entity: AuditEntity.staff,
        entityId: s.name,
        detail: 'PIN reset',
      );
    } catch (e) {
      if (!mounted) return;
      showOperationFailure(
        context,
        title: l10n.settingsPinResetTitle,
        message: l10n.settingsResetPinFailed,
      );
    }
  }

  Future<void> _removeStaff(Staff s) async {
    final l10n = AppLocalizations.of(context);
    final state = context.read<AppState>();
    final ConfirmOutcome outcome = await confirmIrreversible(
      context,
      title: l10n.settingsRemoveStaffTitle,
      message: l10n.settingsRemoveStaffMessage(s.name),
      confirmLabel: l10n.settingsRemoveAction,
      cancelLabel: l10n.actionCancel,
    );
    if (outcome is! ConfirmAccepted) return;
    try {
      await DatabaseHelper.instance.deleteStaffWithTombstone(s);
      // And the cached offline credential, which survives the roster row being
      // relabelled. Without this the removed cashier can still sign in against
      // the keystore fallback, because `login_screen` verifies against it when
      // `staff.pinHash` no longer matches.
      if (s.id != null) {
        await StaffCredentialCache.clearStaffCredentials(s.id!);
      }
      // The NAME, not the id: the tombstone scrubs the row this id pointed at,
      // so a later read resolves to nothing and the log has to carry the name
      // itself.
      await recordActionAudit(
        state,
        action: AuditAction.staffRemoved,
        entity: AuditEntity.staff,
        entityId: s.name,
        detail: s.role,
      );
      if (_backendLinked) {
        try {
          await BackendService.syncStaffToBackend();
        } catch (_) {
          if (!mounted) return;
          showOperationSuccess(
            context,
            title: l10n.settingsStaffRemovedTitle,
            message: l10n.settingsStaffRemovedOffline,
            detailIcon: Icons.cloud_off_outlined,
          );
        }
      }
      await _load();
      if (!mounted) return;
      showOperationSuccess(
        context,
        title: l10n.settingsStaffRemovedTitle,
        message: s.name,
        detailIcon: Icons.person_remove_outlined,
      );
    } catch (e) {
      if (!mounted) return;
      showOperationFailure(
        context,
        title: l10n.settingsStaffRemoveFailedTitle,
        message: l10n.settingsRemoveStaffFailed,
      );
    }
  }

  Future<void> _toggleMpesa(bool value) async {
    // Read before the await.
    final AppState state = context.read<AppState>();
    final l10n = AppLocalizations.of(context);
    _MpesaChannelDetails? setup;
    if (value) {
      setup = await _showMpesaSetupDialog(
        initialChannelType: _mpesaChannelType,
        initialMerchantNumber: _mpesaMerchantNumber,
      );
      if (setup == null || !mounted) return;
    }
    int? channelId = _mpesaChannelId;
    if (value && !_backendLinked) {
      final linked = await _showLinkBackendDialog();
      if (linked != true) return; // user cancelled — leave the toggle off
      _backendLinked = true;
    }
    setState(() => _savingToggle = true);
    try {
      if (_backendLinked) {
        if (value) {
          channelId = await BackendService.registerMpesaChannel(
            channelType: setup!.channelType,
            shortCode: setup.merchantNumber,
          );
        }
        await BackendService.setMpesaEnabled(value, channelId: channelId);
        if (value) {
          await BackendService.syncProductsToBackend();
          await BackendService.syncStaffToBackend();
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('mpesa_enabled_local', value);
      if (value) {
        await DatabaseHelper.instance.setSetting(
          DatabaseHelper.settingMpesaChannelId,
          channelId.toString(),
        );
        await DatabaseHelper.instance.setSetting(
          DatabaseHelper.settingMpesaChannelType,
          setup!.channelType,
        );
        await DatabaseHelper.instance.setSetting(
          DatabaseHelper.settingMpesaMerchantNumber,
          setup.merchantNumber,
        );
      }
      // Turning M-Pesa on or off changes what the till can take, so it is one
      // of the settings whose change an owner would want attributed.
      await recordActionAudit(
        state,
        action: AuditAction.paymentMethodChanged,
        entity: AuditEntity.settings,
        detail: 'M-Pesa ${value ? 'enabled' : 'disabled'}',
      );
      if (mounted) {
        setState(() {
          _mpesaEnabled = value;
          _mpesaChannelId = channelId;
          if (setup != null) {
            _mpesaChannelType = setup.channelType;
            _mpesaMerchantNumber = setup.merchantNumber;
          }
          _backendLinked = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      showOperationFailure(
        context,
        title: l10n.settingsMpesaUpdateFailedTitle,
        message: l10n.settingsMpesaUpdateFailed,
      );
    } finally {
      if (mounted) setState(() => _savingToggle = false);
    }
  }

  Future<_MpesaChannelDetails?> _showMpesaSetupDialog({
    required String initialChannelType,
    required String initialMerchantNumber,
  }) async {
    final merchantController =
        TextEditingController(text: initialMerchantNumber);
    var channelType = initialChannelType == 'Paybill' ? 'Paybill' : 'Till';
    final result = await showDialog<_MpesaChannelDetails>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Set up M-Pesa with PayHero'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Enter the shop’s Till or Paybill number. The backend registers it with PayHero and keeps the API credentials off this till.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'The number must belong to this shop. STK prompts require an online connection at checkout.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: channelType,
                  decoration: const InputDecoration(labelText: 'Channel type'),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: 'Till', child: Text('M-Pesa Till')),
                    DropdownMenuItem(
                        value: 'Paybill', child: Text('M-Pesa Paybill')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => channelType = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: merchantController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: channelType == 'Paybill'
                        ? 'Paybill number'
                        : 'Till number',
                    helperText:
                        'For your records; PayHero uses the channel ID below.',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final merchant = merchantController.text.trim();
                if (!RegExp(r'^\d{5,12}$').hasMatch(merchant)) {
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _MpesaChannelDetails(
                    channelType: channelType,
                    merchantNumber: merchant,
                  ),
                );
              },
              child: const Text('Save channel'),
            ),
          ],
        ),
      ),
    );
    merchantController.dispose();
    return result;
  }

  Future<bool?> _showLinkBackendDialog() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final owner = context.read<AppState>().owner!;
    var submitting = false;
    String? error;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          StatefulBuilder(builder: (dialogContext, setDialogState) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context).settingsConnectMpesaTitle),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                l10n.settingsConnectMpesaMessage,
                style: AppTypography.of(context).bodyMedium,
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: TextStyle(color: AppColors.of(context).danger)),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppLocalizations.of(context).actionCancel)),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      setDialogState(() {
                        submitting = true;
                        error = null;
                      });
                      try {
                        await BackendService.linkShopToBackend(
                          shopName: owner.shopName,
                          ownerName: owner.name,
                          email: owner.email,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (e) {
                        setDialogState(() {
                          submitting = false;
                          error = AppLocalizations.of(context)
                              .settingsConnectFailed;
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(AppLocalizations.of(context).settingsConnectAction),
            ),
          ],
        );
      }),
    );
    return result;
  }

  Future<void> _verifyIdentityOnline() async {
    // Read before the first await: the audit row names the shop, and a
    // BuildContext held across a network call is exactly what this codebase
    // refuses to do.
    final AppState state = context.read<AppState>();
    final Owner owner = state.owner!;
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _verifyingIdentity = true);
    try {
      // 1. The admin PIN, verified against the local hash. The backend cannot
      //    check it — the hash lives in this phone's database — so the till
      //    refuses a wrong one here rather than sending it over the wire.
      //
      //    This is also the ONE place the owner PIN is rate-limited, so it
      //    shares the till-wide lockout the login pad uses. Without it this
      //    dialog was a PIN oracle with no attempt counting: a wrong guess
      //    costs one local PBKDF2 check, is never recorded, and repeats
      //    forever — 10,000 values is minutes of guessing.
      final String? pin = await showVerifyPinSheet(
        context,
        email: PinResetService.maskEmail(owner.email),
        onSubmit: (String entered) =>
            _verifyOwnerPinOrError(entered, owner.pinHash, l10n),
      );
      if (pin == null || !mounted) return;

      // 2. The account and the code. A failure here is the shop's problem to
      //    see (no signal, server not configured, too many codes), so it is
      //    reported as one sentence and the flow stops where it can retry.
      final VerificationChallenge challenge;
      try {
        challenge = await BackendService.requestVerificationCode(
          email: owner.email,
          pin: pin,
          shopName: owner.shopName,
          ownerName: owner.name,
        );
      } on VerificationException catch (error) {
        if (!mounted) return;
        _err(_verificationMessage(l10n, error));
        return;
      } catch (_) {
        if (!mounted) return;
        _err(l10n.settingsIdentityLinkFailed);
        return;
      }
      if (!mounted) return;
      // MASKED. A snackbar is read on a shop floor with people around, and it
      // is the one place the owner's address is shown to anyone in earshot.
      _err(l10n.settingsVerifyCodeSent(PinResetService.maskEmail(owner.email)));

      // 3. The code from the email, and the way to ask for another one. The
      //    dialog stays open on a wrong code, so the owner retypes rather
      //    than starting again.
      final bool verified = await showVerifyCodeSheet(
        context,
        // The server's own mask when it has one, this device's otherwise —
        // never the raw address. A shop that linked before the server started
        // masking has no `maskedEmail`, and falling back to the plain address
        // would show it on a PIN pad.
        maskedEmail: challenge.maskedEmail.isNotEmpty
            ? challenge.maskedEmail
            : PinResetService.maskEmail(owner.email),
        onSubmit: (String code) async {
          try {
            await BackendService.confirmVerificationCode(
              email: owner.email,
              pin: pin,
              code: code,
            );
            return null;
          } on VerificationException catch (error) {
            return _verificationMessage(l10n, error);
          } catch (_) {
            return l10n.settingsIdentityLinkFailed;
          }
        },
        onResend: () async {
          try {
            await BackendService.requestVerificationCode(
              email: owner.email,
              pin: pin,
              shopName: owner.shopName,
              ownerName: owner.name,
            );
            return l10n
                .settingsVerifyCodeSent(PinResetService.maskEmail(owner.email));
          } on VerificationException catch (error) {
            return _verificationMessage(l10n, error);
          } catch (_) {
            return l10n.settingsIdentityLinkFailed;
          }
        },
      );
      if (!verified || !mounted) return;

      await state.loadOwner();
      await state.markIdentityVerified();
      await recordActionAudit(
        state,
        action: AuditAction.identityLinked,
        entity: AuditEntity.identity,
        // No address in the audit detail. This row is readable by anyone the
        // owner shares an activity report with, and an email address is the
        // field that turns a log line into a doxxing.
        detail: 'email verified for this shop',
      );
      if (!mounted) return;
      // The shop's identity is verified. Said on a screen, because this is a
      // thing the owner waited for a code to happen, and a snackbar that
      // vanishes in four seconds is not a record of it.
      showOperationSuccess(
        context,
        title: AppLocalizations.of(context).settingsIdentityVerifiedTitle,
        message: AppLocalizations.of(context).settingsIdentityVerified,
        detailIcon: Icons.verified_outlined,
      );
    } finally {
      if (mounted) setState(() => _verifyingIdentity = false);
    }
  }

  String _verificationMessage(
    AppLocalizations l10n,
    VerificationException error,
  ) =>
      verificationMessage(l10n, error);

  Future<void> _syncNow() async {
    // Capture dependencies before the sync's async gap; they are used again
    // for the audit/result message after the network work completes.
    final AppState state = context.read<AppState>();
    final AppLocalizations l10n = AppLocalizations.of(context);
    final shopName = state.owner!.shopName;
    setState(() {
      _syncing = true;
      _syncStatus = null;
    });
    // The manual action must reconcile every offline queue, not just the
    // legacy Sheets workbook. It is a one-shot sync and does not turn on the
    // recurring automatic-backup preference.
    await AutoSyncService.runNow(force: true);
    final invResult = await _sync.syncInventory(shopName);
    final salesResult = await _sync.syncSales(shopName);
    if (_mpesaEnabled && _backendLinked) {
      try {
        await BackendService.syncProductsToBackend();
      } catch (_) {
        // Sheets/Excel sync result still reported below; backend push
        // failing silently here just means the drift window (documented in
        // the backend README) stays open a bit longer — not fatal.
      }
    }
    if (!mounted) return;
    final String statusLabel = invResult == SyncResult.pushedToSheets &&
            salesResult == SyncResult.pushedToSheets
        ? l10n.settingsSyncSheets
        : (invResult == SyncResult.failed || salesResult == SyncResult.failed)
            ? l10n.settingsSyncFailed
            : l10n.settingsSyncOfflineExcel;
    setState(() {
      _syncing = false;
      _syncStatus = statusLabel;
    });
    // A sync that reports success is a claim about the backend, so the claim is
    // logged with its outcome rather than left as a snackbar that vanishes.
    await recordActionAudit(
      state,
      action: AuditAction.syncSettingsChanged,
      entity: AuditEntity.settings,
      detail: 'manual sync: $statusLabel',
    );
    if (!mounted) return;
    // And the owner is told, on a screen. A sync that pushed nothing and one
    // that pushed everything are very different facts, and the owner pressed
    // the button to find out which.
    showOperationSuccess(
      context,
      title: l10n.settingsSyncDoneTitle,
      message: statusLabel,
      detailIcon: Icons.cloud_sync_outlined,
    );
  }

  Future<void> _setAutoSync(bool value) async {
    // Read before the await: the preference write is the async gap, and the
    // audit row after it must not hold a BuildContext.
    final AppState state = context.read<AppState>();
    await AutoSyncService.setEnabled(value);
    if (mounted) setState(() => _automaticBackupSync = value);
    // A backup that silently stopped happening is indistinguishable from one
    // that never existed, so the toggle's own state is logged.
    await recordActionAudit(
      state,
      action: AuditAction.syncSettingsChanged,
      entity: AuditEntity.settings,
      detail: 'auto-sync ${value ? 'on' : 'off'}',
    );
  }

  Future<void> _exportEncryptedInventory() async {
    final l10n = AppLocalizations.of(context);
    final state = context.read<AppState>();
    try {
      final passphrase = await _backupPassphrase(context, confirm: true);
      if (passphrase == null) return;
      final f = await _excel.exportPortableEncryptedInventory(passphrase);
      await _excel.shareFile(f);
      // The share has already left the device, so the row says a backup WAS
      // produced — the audit is the last thing standing after the share sheet
      // closes.
      await recordActionAudit(
        state,
        action: AuditAction.backupExported,
        entity: AuditEntity.backup,
        detail: 'portable encrypted',
      );
      if (!mounted) return;
      showOperationSuccess(
        context,
        title: l10n.settingsExportDoneTitle,
        message: l10n.settingsExportEncryptedDone,
        detailIcon: Icons.lock_outline,
      );
    } on Object {
      if (!mounted) return;
      showOperationFailure(
        context,
        title: l10n.settingsExportFailedTitle,
        message: l10n.settingsExportFailed,
        onRetry: _exportEncryptedInventory,
      );
    }
  }

  Future<void> _exportFullBackup() async {
    final state = context.read<AppState>();
    try {
      final passphrase = await _backupPassphrase(context, confirm: true);
      if (passphrase == null) return;
      final file = await _excel.exportPortableFullBackup(passphrase);
      await _excel.shareFile(file);
      await recordActionAudit(
        state,
        action: AuditAction.backupExported,
        entity: AuditEntity.backup,
        detail: 'portable full data backup',
      );
    } catch (_) {
      if (mounted) {
        showOperationFailure(
          context,
          title: AppLocalizations.of(context).settingsExportFailedTitle,
          message: AppLocalizations.of(context).settingsExportFailed,
          onRetry: _exportFullBackup,
        );
      }
    }
  }

  Future<void> _exportInventory() async {
    final l10n = AppLocalizations.of(context);
    final state = context.read<AppState>();
    try {
      final f = await _excel.exportInventory();
      await _excel.shareFile(f);
      await recordActionAudit(
        state,
        action: AuditAction.backupExported,
        entity: AuditEntity.backup,
        detail: 'plain workbook',
      );
      if (!mounted) return;
      showOperationSuccess(
        context,
        title: l10n.settingsExportDoneTitle,
        message: l10n.settingsExportInventoryDone,
        detailIcon: Icons.table_chart_outlined,
      );
    } on Object {
      if (!mounted) return;
      showOperationFailure(
        context,
        title: l10n.settingsExportFailedTitle,
        message: l10n.settingsExportFailed,
        onRetry: _exportInventory,
      );
    }
  }

  /// Restores an encrypted backup, reporting how many products came back.
  ///
  /// The barcode-refusal list is part of the result rather than a second
  /// summary: a restored catalogue that silently dropped three codes is a
  /// discrepancy the shop finds at the till a week later.
  Future<void> _restoreEncryptedInventory() async {
    final l10n = AppLocalizations.of(context);
    final state = context.read<AppState>();
    try {
      final passphrase = await _backupPassphrase(context);
      if (passphrase == null) return;
      final n = await _excel.importPortableEncryptedInventory(passphrase);
      if (!mounted) return;
      showOperationSuccess(
        context,
        title: l10n.settingsRestoreDoneTitle,
        message: l10n.settingsRestoredProducts(n),
        detailIcon: Icons.restore_outlined,
      );
      if (!mounted) return;
      // Logged with the count, because a restore that brought back three
      // products of four hundred is the most important row this screen writes.
      await recordActionAudit(
        state,
        action: AuditAction.backupRestored,
        entity: AuditEntity.backup,
        detail: 'encrypted, $n products',
      );
    } on FormatException {
      if (!mounted) return;
      showOperationFailure(
        context,
        title: l10n.settingsRestoreFailedTitle,
        message: l10n.settingsInvalidEncryptedBackup,
        // A malformed file will be malformed again: there is nothing to
        // retry, and a "Try again" button that cannot help is worse than none.
      );
    } catch (_) {
      if (!mounted) return;
      showOperationFailure(
        context,
        title: l10n.settingsRestoreFailedTitle,
        message: l10n.settingsDecryptBackupFailed,
        onRetry: _restoreEncryptedInventory,
      );
    }
  }

  Future<void> _restoreFullBackup() async {
    final state = context.read<AppState>();
    try {
      final passphrase = await _backupPassphrase(context);
      if (passphrase == null) return;
      await _excel.importPortableFullBackup(passphrase);
      await recordActionAudit(
        state,
        action: AuditAction.backupRestored,
        entity: AuditEntity.backup,
        detail: 'portable full data backup',
      );
      if (mounted) {
        showOperationSuccess(
          context,
          title: AppLocalizations.of(context).settingsRestoreDoneTitle,
          message: 'All local shop data was restored.',
          detailIcon: Icons.restore_outlined,
        );
      }
    } on Object {
      if (mounted) {
        showOperationFailure(
          context,
          title: AppLocalizations.of(context).settingsRestoreFailedTitle,
          message: AppLocalizations.of(context).settingsDecryptBackupFailed,
          onRetry: _restoreFullBackup,
        );
      }
    }
  }

  Future<void> _restoreCloudFullBackup() async {
    final state = context.read<AppState>();
    try {
      final passphrase = await _backupPassphrase(context);
      if (passphrase == null) return;
      final restored =
          await BackendService.restorePortableFullBackupFromBackend(passphrase);
      if (!restored) {
        if (mounted) {
          showOperationFailure(
            context,
            title: AppLocalizations.of(context).settingsRestoreFailedTitle,
            message: 'No cloud backup is available for this workspace.',
          );
        }
        return;
      }
      await recordActionAudit(
        state,
        action: AuditAction.backupRestored,
        entity: AuditEntity.backup,
        detail: 'portable cloud full data backup',
      );
      if (mounted) {
        showOperationSuccess(
          context,
          title: AppLocalizations.of(context).settingsRestoreDoneTitle,
          message: 'The latest cloud backup was restored.',
          detailIcon: Icons.cloud_download_outlined,
        );
      }
    } on Object {
      if (mounted) {
        showOperationFailure(
          context,
          title: AppLocalizations.of(context).settingsRestoreFailedTitle,
          message: AppLocalizations.of(context).settingsDecryptBackupFailed,
          onRetry: _restoreCloudFullBackup,
        );
      }
    }
  }

  Future<void> _uploadCloudFullBackup() async {
    final state = context.read<AppState>();
    try {
      final passphrase = await _backupPassphrase(context, confirm: true);
      if (passphrase == null) return;
      await BackendService.syncPortableFullBackupToBackend(passphrase);
      await recordActionAudit(
        state,
        action: AuditAction.backupExported,
        entity: AuditEntity.backup,
        detail: 'portable cloud full data backup',
      );
      if (mounted) {
        showOperationSuccess(
          context,
          title: 'Cloud backup uploaded',
          message:
              'This copy can be restored on another phone with its passphrase.',
          detailIcon: Icons.cloud_upload_outlined,
        );
      }
    } on Object {
      if (mounted) {
        showOperationFailure(
          context,
          title: AppLocalizations.of(context).settingsExportFailedTitle,
          message: AppLocalizations.of(context).settingsExportFailed,
          onRetry: _uploadCloudFullBackup,
        );
      }
    }
  }

  Future<String?> _backupPassphrase(
    BuildContext context, {
    bool confirm = false,
  }) async {
    final first = TextEditingController();
    final second = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(confirm ? 'Protect backup' : 'Unlock backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: first,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Passphrase (8+ characters)'),
            ),
            if (confirm)
              TextField(
                controller: second,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Repeat passphrase'),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (first.text.length < 8 ||
                  (confirm && first.text != second.text)) {
                return;
              }
              Navigator.pop(dialogContext, first.text);
            },
            child: Text(confirm ? 'Protect' : 'Unlock'),
          ),
        ],
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  /// Imports a plain workbook, naming any barcode it refused and why.
  ///
  /// The owner WATCHES this one. An import is the longest thing the app does
  /// on a tap and the only one with nothing to press while it happens, so a
  /// silent import reads as a broken app — and the owner presses the button
  /// again, which is how an import used to be started twice.
  Future<void> _importInventory() async {
    if (_importing) return;
    final l10n = AppLocalizations.of(context);
    final state = context.read<AppState>();
    setState(() => _importing = true);
    _importProgress.value = null;
    try {
      final result = await AppBusy.during(
        () => _excel.importInventory(
          onProgress: (ImportProgress progress) {
            if (!mounted) return;
            _importProgress.value = progress;
          },
        ),
      );
      if (!mounted) return;
      if (!mounted) return;
      final refused = result.refusedBarcodes;
      // One sentence either way. The refusal count is part of the audit row,
      // not just of the snackbar: the snackbar disappears in six seconds, and
      // the question "did this restore drop anything" outlives it.
      final detail = refused.isEmpty
          ? '${result.products} products'
          : '${result.products} products, ${refused.length} barcodes refused';
      if (refused.isEmpty) {
        showOperationSuccess(
          context,
          title: l10n.settingsImportDoneTitle,
          message: l10n.settingsImportedProducts(result.products),
          detailIcon: Icons.upload_file_outlined,
        );
      } else {
        // Each code paired with the product that already owns it, so the owner
        // can fix the workbook instead of guessing which rows were skipped.
        // Alphabetical order, as gen-l10n emits the generated parameters:
        // detail, products, refused.
        showOperationSuccess(
          context,
          title: l10n.settingsImportDoneTitle,
          message: l10n.settingsImportedProductsWithRefused(
            detail,
            result.products,
            l10n.settingsBarcodesRefusedList(refused.length),
          ),
          detailIcon: Icons.upload_file_outlined,
        );
      }
      if (!mounted) return;
      await recordActionAudit(
        state,
        action: AuditAction.backupRestored,
        entity: AuditEntity.backup,
        detail: detail,
      );
    } on UnreadableLayoutException {
      // The one workbook problem with an actionable answer, so it gets its own
      // sentence instead of the generic invalid-workbook one.
      if (!mounted) return;
      showOperationFailure(
        context,
        title: l10n.settingsImportFailedTitle,
        message: l10n.importNotOurFormat,
      );
    } on FormatException {
      if (!mounted) return;
      showOperationFailure(
        context,
        title: l10n.settingsImportFailedTitle,
        message: l10n.settingsInvalidWorkbook,
      );
    } catch (_) {
      if (!mounted) return;
      showOperationFailure(
        context,
        title: l10n.settingsImportFailedTitle,
        message: l10n.settingsImportWorkbookFailed,
        onRetry: _importInventory,
      );
    } finally {
      // The state is cleared whatever happened, so a failed import leaves the
      // button ready for another try. And the screen may be gone by now — the
      // owner walked away — in which case there is nothing to clear.
      _importProgress.value = null;
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  /// The shop switcher.
  ///
  /// Reads the LOCAL REGISTRY, not the backend's shop list. It used to call

  Future<void> _manageShops() async {
    // Read before the first await: the registry is local, but the dialog it
    // populates is built from it and the switch tears the screen down.
    final l10n = AppLocalizations.of(context);
    try {
      final List<LocalShop> shops = await WorkspaceServiceShops.localShops();
      final String activeKey = await WorkspaceService.activeWorkspaceKey();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(l10n.settingsYourShopsTitle),
          content: SizedBox(
            width: 380,
            // A device with one shop is not a broken list: it says so, rather
            // than showing a single row that cannot be switched to anything.
            child: shops.length <= 1
                ? Text(l10n.settingsOneShopOnDevice)
                : ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final LocalShop shop in shops)
                        ListTile(
                          leading: ExcludeSemantics(
                            child: Icon(
                              shop.workspaceKey == activeKey
                                  ? Icons.check_circle
                                  : Icons.store_mall_directory_outlined,
                            ),
                          ),
                          title: Text(
                            // A shop name is typed by a human, and it WRAPS.
                            // Two lines and an ellipsis is a name the owner
                            // cannot read — and the name is how they know which
                            // shop they are about to switch into.
                            shop.shopName,
                          ),
                          // The role, not the tenant id: a shopkeeper
                          // switching shops wants to know what they are, and a
                          // UUID is not that.
                          subtitle: Text(
                            shop.workspaceKey == activeKey
                                ? l10n.settingsCurrentShop
                                : (shop.isBackendLinked
                                    ? l10n.settingsLinkedShop
                                    : l10n.settingsLocalOnlyShop),
                          ),
                          trailing: shop.workspaceKey == activeKey
                              ? null
                              : TextButton(
                                  onPressed: () async =>
                                      _switchToShop(dialogContext, shop),
                                  child: Text(l10n.settingsSwitchAction),
                                ),
                        ),
                    ],
                  ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.settingsCloseAction),
            ),
          ],
        ),
      );
    } catch (_) {
      _err(l10n.settingsLoadShopsFailed);
    }
  }

  Future<void> _switchToShop(BuildContext dialogContext, LocalShop shop) async {
    final l10n = AppLocalizations.of(context);
    // Captured before the await, and used after it: `_err` needs a live
    // ScaffoldMessenger, and the router has to be reachable even if this
    // screen is gone by the time the switch finishes.
    final AppState state = context.read<AppState>();
    final GoRouter router = GoRouter.of(context);
    try {
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      if (!mounted) return;
      // Written BEFORE the switch, because the switch changes which database
      // the row belongs to: after it, this line would log the change into the
      // shop that was just left — and the shop the owner is now in would show
      // nothing at all. The row therefore lives in the shop it describes.
      await recordActionAudit(
        state,
        action: AuditAction.shopSwitched,
        entity: AuditEntity.workspace,
        entityId: shop.workspaceKey,
        detail: shop.shopName,
      );
      // Switching reads the new shop's own data, replaces the session with
      // that shop's owner, and announces the change ONCE — so the app is
      // never caught between shops with nobody signed in.
      await state.switchWorkspace(shop.workspaceKey);
      // And the person lands on the DASHBOARD, not wherever they happened to
      // be. The shop they were in is gone; its settings, its inventory and
      // its reports all belong to the shop they just left, and staying on
      // that branch is how the app ends up showing an empty page.
      router.go(Routes.dashboard);
      if (!mounted) return;
      _err(l10n.settingsSwitchedToShop(shop.shopName));
    } catch (_) {
      if (!mounted) return;
      _err(l10n.settingsSwitchShopFailed);
    }
  }

  Future<void> _changeBusinessProfile() async {
    final AppState state = context.read<AppState>();
    final ShopProfile current = state.shopProfile;
    final AppLocalizations l10n = AppLocalizations.of(context);
    ShopProfile selected = current;
    final ShopProfile? result = await showDialog<ShopProfile>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
          title: Text(l10n.settingsBusinessProfileChangeTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DropdownButtonFormField<ShopProfile>(
                initialValue: selected,
                decoration: InputDecoration(
                  labelText: l10n.shopProfileLabel,
                ),
                items: ShopProfile.values
                    .map((profile) => DropdownMenuItem<ShopProfile>(
                          value: profile,
                          child: Text(profile.displayName),
                        ))
                    .toList(),
                onChanged: (profile) {
                  if (profile != null) {
                    setDialogState(() => selected = profile);
                  }
                },
              ),
              SizedBox(height: AppSpacing.of(context).md),
              Text(l10n.settingsBusinessProfileChangeWarning),
              SizedBox(height: AppSpacing.of(context).sm),
              ProfileChangePreview(current: current, selected: selected),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: Text(l10n.settingsBusinessProfileChangeAction),
            ),
          ],
        ),
      ),
    );
    if (result == null || result == current || !mounted) return;

    await DatabaseHelper.instance.setShopProfile(result);
    state.setShopProfile(result);
    try {
      await BackendService.setBusinessProfile(result);
    } catch (_) {
      // Local shop records remain usable offline; the next sync/retry can
      // reconcile the linked tenant profile.
    }
    await recordActionAudit(
      state,
      action: AuditAction.profileChanged,
      entity: AuditEntity.workspace,
      detail: '${current.displayName} → ${result.displayName}',
    );
    if (mounted) {
      setState(() {});
      _err(l10n.settingsBusinessProfileChanged(result.displayName));
    }
  }

  Future<void> _addShopOnThisDevice() async {
    final previous = context.read<AppState>().owner;
    final previousWorkspace = context.read<AppState>().workspaceKey;
    final l10n = AppLocalizations.of(context);
    // Read before the dialog's async gap: a `BuildContext` does not survive an
    // await, and the reason for a bad PIN has to be said in the language the
    // owner is actually reading.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (previous == null) {
      _err(l10n.settingsSignInBeforeAddingShop);
      return;
    }

    final name = TextEditingController();
    final pin = TextEditingController();
    ShopProfile selectedProfile = ShopProfile.duka;
    // The shop's name AND the PIN that opens it.
    //
    // The PIN is asked for because each shop has its own. One PIN for every
    // shop on the device means a till in the back office opens the till at
    // the counter, and a PIN that is typed forty times a day is worth keeping
    // to the shop it belongs to.
    final _NewShopDetails? details = await showDialog<_NewShopDetails>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(AppLocalizations.of(context).settingsAddShopTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                      controller: name,
                      autofocus: true,
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)
                              .settingsShopNameLabel),
                      autofillHints: const [AutofillHints.organizationName]),
                  SizedBox(height: AppSpacing.of(context).md),
                  StatefulBuilder(builder: (context, setDialogState) {
                    return DropdownButtonFormField<ShopProfile>(
                      initialValue: selectedProfile,
                      decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context).shopProfileLabel,
                        helperText:
                            AppLocalizations.of(context).shopProfileHelp,
                      ),
                      items: ShopProfile.values
                          .map((profile) => DropdownMenuItem<ShopProfile>(
                                value: profile,
                                child: Text(profile.displayName),
                              ))
                          .toList(),
                      onChanged: (profile) {
                        if (profile != null) {
                          setDialogState(() => selectedProfile = profile);
                        }
                      },
                    );
                  }),
                  SizedBox(height: AppSpacing.of(context).md),
                  TextField(
                      controller: pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: PinRules.adminLength,
                      decoration: InputDecoration(
                          labelText:
                              AppLocalizations.of(context).ownerSetupPinLabel),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(PinRules.adminLength),
                      ],
                      autofillHints: const [
                        AutofillHints.newPassword
                      ]),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppLocalizations.of(context).actionCancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(
                        context,
                        _NewShopDetails(
                          name: name.text.trim(),
                          pin: pin.text.trim(),
                          profile: selectedProfile,
                        )),
                    child: Text(AppLocalizations.of(context).actionContinue))
              ],
            ));
    name.dispose();
    pin.dispose();
    if (details == null ||
        details.name.isEmpty ||
        !PinRules.isAdminPin(details.pin)) {
      if (details != null && details.name.isNotEmpty) {
        // The shop name was given but the PIN was not six digits. The dialog
        // is gone, so the reason is said where the owner is still looking.
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.validationPinNotSixDigits)),
        );
      }
      return;
    }
    final String shop = details.name;

    final key = 'local-${DateTime.now().microsecondsSinceEpoch}';
    // A brand-new shop registers with NO tenant. That is the point: the new
    // shop is unlinked until its owner verifies it, and clearing the legacy
    // global key stops it inheriting the shop it was created from.
    await WorkspaceService.register(workspaceKey: key, shopName: shop);
    if (!mounted) return;

    // The switch, the new shop's owner row, and the sign-in happen in ONE
    // operation. It used to be three, with a `if (!mounted) return;` between
    // them — and the redirect that the dropped session caused had already
    // unmounted this screen, so the owner row was never written. The shop
    // existed in the registry with nothing in it, and the next launch said
    // "no account on this device".
    final AppState state = context.read<AppState>();
    final GoRouter router = GoRouter.of(context);
    try {
      await state.switchWorkspace(
        key,
        createOwnerFor: Owner(
          id: 1,
          name: previous.name,
          // The new shop's own PIN, not the old shop's: each shop has its own.
          pinHash: await AuthService.hashPin(details.pin),
          email: previous.email,
          shopName: shop,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      await DatabaseHelper.instance.setShopProfile(details.profile);
      state.setShopProfile(details.profile);
    } catch (e) {
      await rollbackFailedShopCreation(
        state: state,
        workspaceKey: key,
        previousWorkspaceKey: previousWorkspace,
      );
      if (!mounted) return;
      _err(l10n.settingsCreateShopFailed);
      return;
    }

    // Online identity provisioning is opportunistic, exactly as on first-run
    // setup: the shop is fully usable offline and a later attempt can link it.
    try {
      await BackendService.linkShopToBackend(
          shopName: shop,
          ownerName: previous.name,
          email: previous.email,
          businessProfile: details.profile);
    } catch (_) {
      // Deliberately swallowed. Losing the signal must not lose the shop.
    }

    // The person lands on the DASHBOARD of the shop they just made.
    router.go(Routes.dashboard);
    if (!mounted) return;
    _err(l10n.settingsShopReady(shop));
  }

  @override
  Widget build(BuildContext context) {
    // The stateful screen does the async work; this delegates to a widget that
    // takes the loaded values, so the whole presentation can be rendered from a
    // constructed snapshot in a test without a database — the same split the
    // shift screen uses.
    //
    // The two OWNER-ACCOUNT flows below — linking the online identity and
    // deleting the online account — verify against the OWNER's 6-digit PIN.
    // They are gated on the owner SESSION, not on `isAdmin`: a staff member
    // given the Admin role signs in with a 4-digit PIN, and asking them for a
    // PIN only the shop owner holds is a dead end that charges the owner's
    // lockout budget for the attempt.
    final AppState state = context.watch<AppState>();
    final bool ownerSession = state.isOwnerSession;
    return SettingsPanel(
      identityLinkPending: state.identityLinkPending,
      identityVerified: state.identityVerified,
      verifyingIdentity: _verifyingIdentity,
      onVerifyIdentity: ownerSession ? _verifyIdentityOnline : null,
      staff: _staff,
      onAddStaff: _addStaff,
      onResetPin: _resetPin,
      onRemoveStaff: _removeStaff,
      onOpenPermissions:
          ownerSession ? () => context.push(Routes.permissionsMatrix) : null,
      mpesaEnabled: _mpesaEnabled,
      mpesaChannelId: _mpesaChannelId,
      mpesaChannelType: _mpesaChannelType,
      mpesaMerchantNumber: _mpesaMerchantNumber,
      savingPaymentToggle: _savingToggle,
      onToggleMpesa: _toggleMpesa,
      printer: _printer,
      printerBusy: _printerBusy,
      onPairPrinter: _chooseAndPairPrinter,
      onTestPrint: _testPrint,
      onSavePrinter: _savePrinter,
      cashDrawerEnabled: _cashDrawerEnabled,
      cashDrawerOnCashSale: _cashDrawerOnCashSale,
      cashDrawerPin: _cashDrawerPin,
      cashDrawerOnMs: _cashDrawerOnMs,
      cashDrawerOffMs: _cashDrawerOffMs,
      onToggleCashDrawer: ownerSession ? _toggleCashDrawer : null,
      vatRatePercent: _vatRatePercent,
      tin: _tin,
      tillCode: _tillCode,
      onOpenTaxSettings: _openTaxSettings,
      creditEnabled: _creditEnabled,
      creditDefaultLimitMinor: _creditDefaultLimitMinor,
      expenseApprovalLimitMinor: _expenseApprovalLimitMinor,
      creditLimitMode: _creditLimitMode,
      creditCashiersAllowed: _creditCashiersAllowed,
      creditReminderTemplate: _creditReminderTemplate,
      onEditCreditSettings: ownerSession ? _editCreditSettings : null,
      onEditExpenseApprovalLimit:
          ownerSession ? _editExpenseApprovalLimit : null,
      discountsEnabled: _discountsEnabled,
      cashierDiscountPercent: _cashierDiscountPercent,
      managerDiscountPercent: _managerDiscountPercent,
      onEditDiscountSettings: ownerSession ? _editDiscountSettings : null,
      autoSyncEnabled: _automaticBackupSync,
      syncing: _syncing,
      syncStatus: _syncStatus,
      onSetAutoSync: _setAutoSync,
      onSyncNow: _syncNow,
      onExportEncrypted: _exportEncryptedInventory,
      onRestoreEncrypted: _restoreEncryptedInventory,
      onExportFullBackup: _exportFullBackup,
      onRestoreFullBackup: _restoreFullBackup,
      onUploadCloudFullBackup: ownerSession && state.identityVerified
          ? _uploadCloudFullBackup
          : null,
      onRestoreCloudFullBackup: ownerSession && state.identityVerified
          ? _restoreCloudFullBackup
          : null,
      onExport: _exportInventory,
      onImport: _importInventory,
      onSeedBlackbee: ownerSession && context.read<AppState>().shopProfile == ShopProfile.drinks
          ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BlackbeeSeedScreen(),
                ),
              )
          : null,
      importing: _importing,
      importProgress: _importProgress,
      onEraseBackups: _eraseEncryptedBackups,
      onDeleteAccount: ownerSession ? _deleteOnlineAccount : null,
      accountDeleting: _deletingAccount,
      onAddShop: _addShopOnThisDevice,
      onManageShops: _manageShops,
      onChangeBusinessProfile: ownerSession ? _changeBusinessProfile : null,
      onOpenPortfolio: () => context.push(Routes.portfolio),
      onOpenActivity: () => context.push(Routes.activity),
      onOpenIncomingPayments: () => context.push(Routes.incomingPayments),
      onOpenSyncCenter: () => context.push(Routes.syncCenter),
    );
  }

  Future<void> _toggleCashDrawer({
    bool? enabled,
    bool? onCashSale,
    int? pin,
    int? onMs,
    int? offMs,
  }) async {
    final AppState state = context.read<AppState>();
    final db = DatabaseHelper.instance;
    if (enabled != null) {
      await db.setSetting(
          DatabaseHelper.settingCashDrawerEnabled, enabled ? '1' : '0');
    }
    if (onCashSale != null) {
      await db.setSetting(
          DatabaseHelper.settingCashDrawerOnCashSale, onCashSale ? '1' : '0');
    }
    if (pin != null) {
      await db.setSetting(DatabaseHelper.settingCashDrawerPin, '$pin');
    }
    if (onMs != null) {
      await db.setSetting(DatabaseHelper.settingCashDrawerOnMs, '$onMs');
    }
    if (offMs != null) {
      await db.setSetting(DatabaseHelper.settingCashDrawerOffMs, '$offMs');
    }
    await recordActionAudit(
      state,
      action: AuditAction.printerSaved,
      entity: AuditEntity.settings,
      detail: 'cash drawer ${enabled ?? _cashDrawerEnabled ? 'on' : 'off'}',
    );
    await _load();
  }
}

/// The before/after preview shown before an owner commits a profile change.
/// Kept as a value widget so the lifecycle contract is directly testable and
/// cannot silently regress into a warning-only dialog.
class ProfileChangePreview extends StatelessWidget {
  const ProfileChangePreview({
    required this.current,
    required this.selected,
    super.key,
  });

  final ShopProfile current;
  final ShopProfile selected;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.settingsBusinessProfilePreviewTitle,
          style: AppTypography.of(context).titleSmall,
        ),
        SizedBox(height: AppSpacing.of(context).xs),
        Text(
          l10n.settingsBusinessProfilePreviewNavigation(
            current.navigation.showInventory
                ? l10n.settingsBusinessProfileStock
                : l10n.settingsBusinessProfileMoneyFirst,
            selected.navigation.showInventory
                ? l10n.settingsBusinessProfileStock
                : l10n.settingsBusinessProfileMoneyFirst,
          ),
        ),
        Text(
          l10n.settingsBusinessProfilePreviewTerminology(
            current.terminology.product,
            selected.terminology.product,
          ),
        ),
      ],
    );
  }
}

/// Restores the pre-creation state after a shop creation transaction fails.
///
/// This is the one rollback path used by Add Shop: remove the exact database,
/// remove the exact registry entry, then re-open the shop the owner was using.
/// The order prevents a deleted workspace from remaining the active database.
Future<void> rollbackFailedShopCreation({
  required AppState state,
  required String workspaceKey,
  required String previousWorkspaceKey,
}) async {
  await DatabaseHelper.deleteWorkspace(workspaceKey);
  await WorkspaceService.unregister(workspaceKey);
  try {
    await state.switchWorkspace(previousWorkspaceKey);
  } catch (_) {
    // The registry is already repaired; the next launch can recover the
    // previous workspace even if reopening it fails in this error path.
  }
}

/// The whole screen as one constructed value.
///
/// Split from [SettingsScreen] so the presentation can be rendered from a value
/// rather than from a database read in `initState`. Every field is a loaded
/// value or a callback: the panel holds no state and reads nothing, which is
/// what lets a test assert the layout without seeding a shop.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.identityLinkPending,
    required this.verifyingIdentity,
    required this.onVerifyIdentity,
    required this.identityVerified,
    required this.staff,
    required this.onAddStaff,
    required this.onResetPin,
    required this.onRemoveStaff,
    this.onOpenPermissions,
    required this.mpesaEnabled,
    this.mpesaChannelId,
    this.mpesaChannelType = 'Till',
    this.mpesaMerchantNumber = '',
    required this.savingPaymentToggle,
    required this.onToggleMpesa,
    required this.printer,
    required this.printerBusy,
    required this.onPairPrinter,
    required this.onTestPrint,
    required this.onSavePrinter,
    required this.vatRatePercent,
    required this.tin,
    required this.tillCode,
    required this.onOpenTaxSettings,
    this.creditEnabled = false,
    this.creditDefaultLimitMinor = 0,
    this.expenseApprovalLimitMinor = 500000,
    this.creditLimitMode = 'block',
    this.creditCashiersAllowed = false,
    this.creditReminderTemplate = '',
    this.onEditCreditSettings,
    this.onEditExpenseApprovalLimit,
    this.discountsEnabled = false,
    this.cashierDiscountPercent = 0,
    this.managerDiscountPercent = 0,
    this.onEditDiscountSettings,
    this.cashDrawerEnabled = false,
    this.cashDrawerOnCashSale = false,
    this.cashDrawerPin = 0,
    this.cashDrawerOnMs = 50,
    this.cashDrawerOffMs = 500,
    this.onToggleCashDrawer,
    required this.autoSyncEnabled,
    required this.syncing,
    required this.syncStatus,
    required this.onSetAutoSync,
    required this.onSyncNow,
    this.onOpenIncomingPayments,
    this.onOpenSyncCenter,
    required this.onExportEncrypted,
    required this.onRestoreEncrypted,
    this.onExportFullBackup,
    this.onRestoreFullBackup,
    this.onUploadCloudFullBackup,
    this.onRestoreCloudFullBackup,
    required this.onExport,
    required this.onImport,
    this.onSeedBlackbee,
    required this.importing,
    required this.importProgress,
    required this.onEraseBackups,
    required this.onDeleteAccount,
    required this.accountDeleting,
    required this.onAddShop,
    required this.onManageShops,
    this.onChangeBusinessProfile,
    required this.onOpenPortfolio,
    required this.onOpenActivity,
  });

  final bool identityLinkPending;
  final bool verifyingIdentity;

  /// Opens the online-identity verification flow, or NULL when this session is
  /// not the shop owner's. The flow proves itself with the OWNER's 6-digit
  /// PIN, so a manager or an admin-role staff account — who holds a 4-digit
  /// PIN — is not offered a door they cannot open.
  final Future<void> Function()? onVerifyIdentity;

  /// Whether the emailed code has been presented and accepted. The until-then
  /// gate on everything that needs an authoritative online identity:
  /// automatic backups, the cross-shop analytics the portfolio screen reads,
  /// and auto-update.
  final bool identityVerified;

  final List<Staff> staff;
  final Future<void> Function() onAddStaff;
  final void Function(Staff) onResetPin;
  final Future<void> Function(Staff) onRemoveStaff;
  final VoidCallback? onOpenPermissions;

  final bool mpesaEnabled;
  final int? mpesaChannelId;
  final String mpesaChannelType;
  final String mpesaMerchantNumber;
  final bool savingPaymentToggle;
  final Future<void> Function(bool) onToggleMpesa;

  final PrinterConfig printer;
  final bool printerBusy;
  final Future<void> Function() onPairPrinter;
  final Future<void> Function() onTestPrint;
  final Future<void> Function(PrinterConfig) onSavePrinter;

  final int vatRatePercent;
  final String tin;
  final String tillCode;
  final Future<void> Function() onOpenTaxSettings;

  final bool creditEnabled;
  final int creditDefaultLimitMinor;
  final int expenseApprovalLimitMinor;
  final String creditLimitMode;
  final bool creditCashiersAllowed;
  final String creditReminderTemplate;
  final Future<void> Function()? onEditCreditSettings;
  final Future<void> Function()? onEditExpenseApprovalLimit;
  final bool discountsEnabled;
  final int cashierDiscountPercent;
  final int managerDiscountPercent;
  final Future<void> Function()? onEditDiscountSettings;
  final bool cashDrawerEnabled;
  final bool cashDrawerOnCashSale;
  final int cashDrawerPin;
  final int cashDrawerOnMs;
  final int cashDrawerOffMs;
  final Future<void> Function(
      {bool? enabled,
      bool? onCashSale,
      int? pin,
      int? onMs,
      int? offMs})? onToggleCashDrawer;

  final bool autoSyncEnabled;
  final bool syncing;
  final String? syncStatus;
  final Future<void> Function(bool) onSetAutoSync;
  final Future<void> Function() onSyncNow;
  final VoidCallback? onOpenIncomingPayments;
  final VoidCallback? onOpenSyncCenter;

  final Future<void> Function() onExportEncrypted;
  final Future<void> Function() onRestoreEncrypted;
  final Future<void> Function()? onExportFullBackup;
  final Future<void> Function()? onRestoreFullBackup;
  final Future<void> Function()? onUploadCloudFullBackup;
  final Future<void> Function()? onRestoreCloudFullBackup;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final VoidCallback? onSeedBlackbee;

  /// Whether an import is running.
  final bool importing;

  /// Where it has got to.
  final ValueListenable<ImportProgress?> importProgress;

  final Future<void> Function() onEraseBackups;

  /// Deletes the online account and erases what this shop held. NULL when
  /// this session is not the shop owner's — the action proves itself with the
  /// OWNER's 6-digit PIN, so it is not offered to anyone else.
  final Future<void> Function()? onDeleteAccount;

  /// True while a deletion is running, so the row can be disabled rather than
  /// appearing to have been ignored.
  final bool accountDeleting;

  final Future<void> Function() onAddShop;
  final Future<void> Function() onManageShops;
  final Future<void> Function()? onChangeBusinessProfile;
  final VoidCallback onOpenPortfolio;
  final VoidCallback onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // An unverified identity is the one condition on this screen that is the
    // shop's problem rather than the phone's, so it leads instead of sitting in
    // its own section to be scrolled past.
    return SectionedPage(
      maxContentWidth: 880,
      sections: <Widget>[
        // The screen's NAME, large and on the canvas.
        //
        // It used to be a brand lockup: the product's own name, in small caps,
        // where the screen's name should have been. A person who opened
        // Settings to find one thing had to read past the branding to find out
        // where they were.
        ScreenTitle(title: l10n.navSettings),
        if (identityLinkPending && onVerifyIdentity != null)
          _IdentityBanner(busy: verifyingIdentity, onVerify: onVerifyIdentity!),
        _ShopsPanel(
          onAddShop: onAddShop,
          onManage: onManageShops,
          onChangeProfile: onChangeBusinessProfile,
          onOpenPortfolio: onOpenPortfolio,
          onOpenActivity: onOpenActivity,
        ),
        _StaffPanel(
          staff: staff,
          onAdd: onAddStaff,
          onResetPin: onResetPin,
          onRemove: onRemoveStaff,
          onOpenPermissions: onOpenPermissions,
        ),
        _PaymentsPanel(
          mpesaEnabled: mpesaEnabled,
          mpesaChannelId: mpesaChannelId,
          mpesaChannelType: mpesaChannelType,
          mpesaMerchantNumber: mpesaMerchantNumber,
          saving: savingPaymentToggle,
          onToggleMpesa: onToggleMpesa,
        ),
        _PrinterPanel(
          printer: printer,
          busy: printerBusy,
          onPair: onPairPrinter,
          onTestPrint: onTestPrint,
          onSave: onSavePrinter,
        ),
        if (onToggleCashDrawer != null)
          _CashDrawerPanel(
            enabled: cashDrawerEnabled,
            onCashSale: cashDrawerOnCashSale,
            pin: cashDrawerPin,
            onMs: cashDrawerOnMs,
            offMs: cashDrawerOffMs,
            onChanged: onToggleCashDrawer!,
          ),
        _TaxPanel(
          vatRatePercent: vatRatePercent,
          tin: tin,
          tillCode: tillCode,
          onOpen: onOpenTaxSettings,
        ),
        if (onEditCreditSettings != null)
          _CreditPanel(
            enabled: creditEnabled,
            defaultLimitMinor: creditDefaultLimitMinor,
            limitMode: creditLimitMode,
            cashiersAllowed: creditCashiersAllowed,
            reminderTemplate: creditReminderTemplate,
            onEdit: onEditCreditSettings!,
          ),
        if (onEditExpenseApprovalLimit != null)
          _ExpenseApprovalPanel(
            limitMinor: expenseApprovalLimitMinor,
            onEdit: onEditExpenseApprovalLimit!,
          ),
        if (onEditDiscountSettings != null)
          _DiscountPanel(
            enabled: discountsEnabled,
            cashierPercent: cashierDiscountPercent,
            managerPercent: managerDiscountPercent,
            onEdit: onEditDiscountSettings!,
          ),
        _SyncPanel(
          identityVerified: identityVerified,
          enabled: autoSyncEnabled,
          syncing: syncing,
          status: syncStatus,
          onToggle: onSetAutoSync,
          onSyncNow: onSyncNow,
          onOpenIncomingPayments: onOpenIncomingPayments,
          onOpenSyncCenter: onOpenSyncCenter,
        ),
        _BackupPanel(
          onOpenDiagnostics: () => context.push(Routes.diagnostics),
          onExportEncrypted: onExportEncrypted,
          onRestoreEncrypted: onRestoreEncrypted,
          onExportFullBackup: onExportFullBackup,
          onRestoreFullBackup: onRestoreFullBackup,
          onUploadCloudFullBackup: onUploadCloudFullBackup,
          onRestoreCloudFullBackup: onRestoreCloudFullBackup,
          onExport: onExport,
          onImport: onImport,
          onSeedBlackbee: onSeedBlackbee,
          onErase: onEraseBackups,
          importing: importing,
          importProgress: importProgress,
        ),
        _AccountPanel(
          onDeleteAccount: onDeleteAccount,
          deleting: accountDeleting,
          onOpenProfile: () => context.push(Routes.profile),
        ),
        const _UpdatesPanel(),
        const _AboutFooter(),
      ],
    );
  }
}

/// The online account: the PIN recovery, and the way out.
///
/// Kept as its own section rather than folded into the backup panel because it
/// is the only place in Settings where an action is irreversible. Putting it
/// next to the export buttons would make "delete account" look like one more
/// data operation with an undo, and nothing here has an undo.
class _AccountPanel extends StatelessWidget {
  const _AccountPanel({
    required this.onDeleteAccount,
    required this.deleting,
    required this.onOpenProfile,
  });

  /// Null when this session is not the shop owner's: the row is not rendered.
  final Future<void> Function()? onDeleteAccount;

  /// Opens the owner's account.
  final VoidCallback onOpenProfile;

  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    return _SettingsSection(
      title: l10n.settingsAccountSection,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(l10n.settingsProfileRow),
            onTap: onOpenProfile,
          ),
          // Forgotten-PIN recovery is NOT here, though it belongs to the same
          // idea. The only way to reach this screen is to unlock the till, and
          // unlocking it needs the PIN — so recovery has to be on the login pad
          // (see `_LoginScreenState._forgotPin`), behind nothing.
          //
          // The delete row only exists for the OWNER session. A staff account
          // has no online account of its own to delete, and the action asks
          // for the owner's PIN, which a staff account does not hold.
          if (onDeleteAccount != null)
            ListTile(
              leading:
                  Icon(Icons.delete_forever_outlined, color: colors.danger),
              title: Text(
                l10n.settingsDeleteAccountAction,
                style: TextStyle(color: colors.danger),
              ),
              enabled: !deleting,
              onTap: deleting ? null : onDeleteAccount,
            ),
        ],
      ),
    );
  }
}

class _UpdatesPanel extends StatelessWidget {
  const _UpdatesPanel();

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    // Watching here rebuilds the whole panel whenever the service changes,
    // which is the right scope: every row in it is a view of that service.
    //
    // This used to re-provide the service with `ChangeNotifierProvider.value`,
    // which was a second, redundant provider wrapping one that already exists
    // in the composition root — and it threw from inside the panel's build.
    context.watch<AppUpdateService>();
    return _SettingsSection(
      title: AppLocalizations.of(context).settingsUpdatesSection,
      child: Padding(
        padding: EdgeInsetsDirectional.only(bottom: spacing.sm),
        child: const _UpdateRows(),
      ),
    );
  }
}

/// The state of the check, and the actions it offers.
class _UpdateRows extends StatelessWidget {
  const _UpdateRows();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final service = context.watch<AppUpdateService>();
    final release = service.pendingRelease;
    final announcement = service.announcement;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (announcement != null) ...<Widget>[
          Card(
            child: ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: Text(announcement.title),
              subtitle: Text(announcement.body),
            ),
          ),
          SizedBox(height: AppSpacing.of(context).sm),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.system_update_outlined),
          title: Text(l10n.settingsUpdatesCheck),
          subtitle: Text(_statusText(service, l10n)),
          trailing: service.busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: service.busy ? null : () => service.checkForUpdate(),
        ),
        if (service.progress != null) ...<Widget>[
          SizedBox(height: AppSpacing.of(context).sm),
          _DownloadBar(progress: service.progress!),
        ],
        if (service.downloadedApk != null) ...<Widget>[
          SizedBox(height: AppSpacing.of(context).sm),
          FilledButton.icon(
            onPressed: service.busy ? null : () => _install(context),
            icon: const Icon(Icons.install_mobile_outlined),
            label: Text(l10n.settingsUpdatesInstall),
          ),
        ],
        SizedBox(height: AppSpacing.of(context).md),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.autorenew_outlined),
          title: Text(l10n.settingsUpdatesAutoLabel),
          subtitle: Text(l10n.settingsUpdatesAutoSubtitle),
          trailing: Switch(
            value: service.autoUpdateEnabled,
            onChanged: service.busy
                ? null
                : (value) => service.autoUpdateEnabled = value,
          ),
        ),
        if (release != null) ...<Widget>[
          SizedBox(height: AppSpacing.of(context).md),
          Text(release.notes.isEmpty
              ? l10n.settingsUpdatesNoNotes
              : release.notes),
          SizedBox(height: AppSpacing.of(context).sm),
        ],
      ],
    );
  }

  /// One line describing where things stand.
  String _statusText(AppUpdateService service, AppLocalizations l10n) {
    final check = service.check;
    if (check is UpdateAvailable) {
      return l10n.settingsUpdatesAvailable(check.release.versionName);
    }
    if (check is UpdateCheckFailed) {
      // A reason the owner can act on, not the server's own words.
      //
      // It used to be the raw cause: "manifest 404", "manifest not JSON", or
      // a socket exception's own sentence, handed to a shopkeeper in the one
      // place they might look for help. The technical detail is in the log,
      // where a developer can read it.
      return l10n.settingsUpdatesFailed(
        check.failure == UpdateCheckFailure.unreachable
            ? l10n.settingsUpdatesReasonUnreachable
            : l10n.settingsUpdatesReasonMalformed,
      );
    }
    if (service.downloadedApk != null) {
      return l10n.settingsUpdatesReady;
    }
    return l10n.settingsUpdatesCurrent(
        service.currentVersionName ?? l10n.settingsUpdatesUnknownVersion);
  }

  /// Asks the OS to install the downloaded APK.
  ///
  /// A refusal is reported AS a refusal rather than swallowed: the two causes
  /// are a signing-key change and a build number that is not higher, and both
  /// mean this shop can never update in place — which is exactly the situation
  /// the owner has to be told about rather than retrying into forever.
  Future<void> _install(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<AppUpdateService>();
    try {
      final granted = await service.installDownloaded();
      if (!granted) {
        // The permission was refused on the system screen.
        final opened = await service.openInstallPermissionSettings();
        messenger.showSnackBar(
          SnackBar(
            content: Text(opened
                ? l10n.settingsUpdatesPermissionNeeded
                : l10n.settingsUpdatesPermissionManual),
          ),
        );
      }
    } on UpdateException {
      // The specific cause is deliberately not shown to the owner: a key change
      // and a lower build number are both "ask the developer", and a stack of
      // exception types on a till is noise. It is in the log line the exception
      // carries.
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsUpdatesRefused)),
      );
    }
  }
}

/// The import's progress: what it is doing, and how far.
///
/// The stage is named, because "38%" on its own says nothing about whether
/// the app is reading the file or writing the products — and those are
/// different failures if it stops there.
class _ImportProgressBar extends StatelessWidget {
  const _ImportProgressBar({required this.progress});

  final ValueListenable<ImportProgress?> progress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ImportProgress?>(
      valueListenable: progress,
      builder: (
        BuildContext context,
        ImportProgress? step,
        Widget? child,
      ) =>
          _bar(context, step),
    );
  }

  Widget _bar(BuildContext context, ImportProgress? step) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    final String stage = step == null
        ? l10n.settingsImportStageReading
        : switch (step.stage) {
            ImportStage.reading => l10n.settingsImportStageReading,
            ImportStage.parsing => l10n.settingsImportStageParsing,
            ImportStage.writing => l10n.settingsImportStageWriting,
            ImportStage.barcodes => l10n.settingsImportStageBarcodes,
            ImportStage.variants => l10n.settingsImportStageVariants,
            ImportStage.done => l10n.settingsImportStageDone,
          };
    final double? fraction = step?.fraction;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          liveRegion: true,
          label: fraction == null
              ? stage
              : l10n.settingsImportProgressPercent(
                  stage, (fraction * 100).round()),
          child: ExcludeSemantics(
            child: ClipRRect(
              // The chip radius from the shape scale, not a literal: 999 is a
              // magic number that means "as round as it goes" and belongs to
              // the scale, where a designer can change it once.
              borderRadius: AppShapes.of(context).chipRadius,
              child: LinearProgressIndicator(
                // An indeterminate bar for the stages that have no measure,
                // and a real one for the stages that do.
                value: fraction,
                minHeight: 6,
                backgroundColor: colors.surfaceSunken,
                valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
              ),
            ),
          ),
        ),
        SizedBox(height: spacing.sm),
        Text(
          fraction == null
              ? stage
              : l10n.settingsImportProgressPercent(
                  stage, (fraction * 100).round()),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceMuted,
              ),
        ),
      ],
    );
  }
}

/// The download's progress, with a byte count so a stalled bar is visible.
class _DownloadBar extends StatelessWidget {
  const _DownloadBar({required this.progress});

  final UpdateProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fraction = progress.fraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ClipRRect(
          borderRadius: AppShapes.of(context).barRadius,
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
          ),
        ),
        SizedBox(height: AppSpacing.of(context).xs),
        Text(
          fraction == null
              ? l10n.settingsUpdatesDownloadingUnknown
              : l10n.settingsUpdatesDownloading((fraction * 100).round()),
          style: AppTypography.of(context).bodySmall,
        ),
      ],
    );
  }
}

class _PrinterChooser extends StatefulWidget {
  const _PrinterChooser({
    required this.printer,
    required this.selectedAddress,
  });

  final PrinterService printer;
  final String? selectedAddress;

  @override
  State<_PrinterChooser> createState() => _PrinterChooserState();
}

class _PrinterChooserState extends State<_PrinterChooser> {
  /// The scan in flight.
  ///
  /// HELD HERE, not handed to a `FutureBuilder`: a builder is given a new
  /// future on every build and starts over, so the scan would re-run — and the
  /// dialog would flicker between "scanning" and "found" — on every rebuild.
  /// The future is attached to ONCE, and its answer arrives through
  /// [_onScanned].
  late Future<List<PrinterDevice>> _devices;

  /// What the scan found. Null until it answers, and empty when it answered
  /// with nothing.
  List<PrinterDevice>? _found;

  /// True when the scan FAILED, as opposed to finding nothing.
  ///
  /// Two different facts: a shop with no printer paired is told how to pair
  /// one, and a shop whose scan broke is told to try again.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _devices = widget.printer.pairedDevices();
    _devices.then(_onScanned, onError: _onFailed);
  }

  void _rescan() {
    setState(() {
      _found = null;
      _failed = false;
      _devices = widget.printer.pairedDevices();
    });
    _devices.then(_onScanned, onError: _onFailed);
  }

  /// The scan's answer, applied once.
  ///
  /// `mounted` first: the dialog can be dismissed while the scan is in
  /// flight, and a widget that is already gone must not be told about it.
  void _onScanned(List<PrinterDevice> devices) {
    if (!mounted) return;
    setState(() => _found = devices);
  }

  void _onFailed(Object _) {
    if (!mounted) return;
    setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final List<PrinterDevice>? found = _found;

    return AlertDialog(
      title: Text(l10n.settingsChoosePrinter),
      contentPadding:
          EdgeInsetsDirectional.only(top: spacing.md, bottom: spacing.sm),
      content: SizedBox(
        width: double.maxFinite,
        child: _failed
            ? Padding(
                padding: EdgeInsets.all(spacing.md),
                child: Text(l10n.settingsPrinterScanFailed),
              )
            : found == null
                ? Padding(
                    padding: EdgeInsets.all(spacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : found.isEmpty
                    ? Padding(
                        padding: EdgeInsets.all(spacing.md),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(l10n.settingsNoPairedPrinters),
                            SizedBox(height: spacing.sm),
                            // Says what to DO, not just what is wrong. The
                            // printer is paired in Android's own Bluetooth
                            // settings, and pointing at that is the difference
                            // between a dead end and an instruction.
                            Text(
                              l10n.settingsNoPairedPrintersHint,
                              style: AppTypography.of(context)
                                  .bodySmall
                                  ?.copyWith(
                                      color:
                                          AppColors.of(context).onSurfaceMuted),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: found.length,
                        itemBuilder: (BuildContext context, int i) {
                          final device = found[i];
                          return SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, device),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.print_outlined),
                              title: Text(device.label),
                              subtitle: Text(device.address),
                              trailing: widget.selectedAddress == device.address
                                  ? const Icon(Icons.check)
                                  : null,
                            ),
                          );
                        },
                      ),
      ),
      actions: <Widget>[
        TextButton.icon(
          onPressed: _rescan,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.settingsPrinterRescan),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
      ],
    );
  }
}

class _AboutFooter extends StatefulWidget {
  const _AboutFooter();

  @override
  State<_AboutFooter> createState() => _AboutFooterState();
}

class _AboutFooterState extends State<_AboutFooter> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {
      // A till with no Play Store services installed has no package info. The
      // footer still renders; it just says less.
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      children: <Widget>[
        SizedBox(height: AppSpacing.of(context).sm),
        // "Powered by Nerva" FIRST, and the app name under it.
        //
        // The attribution is the line that says who built the thing, and the
        // app name is the thing being built. Reading them in that order says
        // "this is Nerva's app" before it says what the app is called — which
        // is the order a person reads a credit in.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: PoweredByNerva(
            style: AppTypography.of(context).bodySmall,
            alignment: CrossAxisAlignment.center,
          ),
        ),
        SizedBox(height: AppSpacing.of(context).xs),
        // The app name and the version as one labelled line rather than two
        // text runs merged with spaces: a screen reader stops after the name
        // and a reader comparing versions stops in the right place.
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: SimplePosBrand.appName,
                style: AppTypography.of(context).labelLarge,
              ),
              if (_version.isNotEmpty)
                TextSpan(
                  text: ' ${l10n.settingsVersionLabel(_version)}',
                  style: AppTypography.of(context).labelMedium,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StaffDialog extends StatefulWidget {
  final String? existingName;
  final bool pinOnly;
  const _StaffDialog({this.existingName, this.pinOnly = false});
  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  String _role = 'cashier';

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.pinOnly
            ? l10n.settingsResetPinTitle(widget.existingName ?? '')
            : l10n.settingsAddStaffAction,
      ),
      // The same field rhythm as the product editor, so a form's spacing is a
      // property of the app rather than of whichever screen you happen to be on.
      // These three used to sit edge to edge: the floating label of each field
      // overlapped the border of the one above it, which is the congestion
      // the inventory form was fixed for.
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!widget.pinOnly) ...[
            TextField(
                controller: _name,
                decoration: InputDecoration(
                    labelText:
                        AppLocalizations.of(context).settingsStaffNameLabel),
                autofillHints: const [AutofillHints.name]),
            SizedBox(height: AppSpacing.of(context).md),
            DropdownButtonFormField<String>(
                initialValue: ShopRole.parse(_role).wire,
                decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).settingsRoleLabel),
                items: [
                  // Built from ShopRole.assignable rather than a literal list, so
                  // a role added there cannot be forgotten here. Admin is
                  // excluded from that list on purpose: the owner already holds it,
                  // and it sits below as a separate, clearly-labelled choice so
                  // handing over full admin rights is deliberate rather than a
                  // mis-tap between two adjacent dropdown entries.
                  ...ShopRole.assignable.map(
                    (role) => DropdownMenuItem(
                      value: role.wire,
                      child: Text(role.label),
                    ),
                  ),
                  DropdownMenuItem(
                    value: ShopRole.admin.wire,
                    child:
                        Text(l10n.settingsRoleAdminFull(ShopRole.admin.label)),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _role = value);
                }),
          ],
          SizedBox(height: AppSpacing.of(context).md),
          TextField(
              controller: _pin,
              decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).settingsPinLabel),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              autofillHints: const [AutofillHints.oneTimeCode]),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).actionCancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'name': widget.existingName ?? _name.text.trim(),
            'pin': _pin.text,
            'role': _role
          }),
          child: Text(AppLocalizations.of(context).settingsSaveAction),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sections
//
// Each section is one widget class that renders a SurfaceCard behind a
// SectionHeader, and takes callbacks up rather than reaching into the screen's
// state: the rows stay presentation, and the screen keeps every rule it had.
// ---------------------------------------------------------------------------

/// One settings section: a header, optional help, and a card of rows.
/// A settings section: a heading and its rows.
///
/// No explanatory text under the heading. The screen is a list of settings, and
/// a paragraph under each heading is a design that assumes the reader arrived
/// wanting to be taught. They did not: they came to turn something on. Where a
/// setting genuinely cannot be guessed — pairing a printer, why backups are
/// locked — the row's own tap explains it, at the moment it is relevant.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(padding: EdgeInsets.zero, label: title),
        SizedBox(height: AppSpacing.of(context).sm),
        // The transparent Material is not decoration: an `InkWell` inside a
        // card needs a Material ancestor to draw its splash, and a settings
        // section is exactly a card of tappable rows.
        SurfaceCard(
          child: Material(
            type: MaterialType.transparency,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _IdentityBanner extends StatelessWidget {
  const _IdentityBanner({required this.busy, required this.onVerify});

  final bool busy;
  final Future<void> Function() onVerify;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StatusTone tone = StatusTone.warning;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // The glyph is the first of three channels: it survives a
              // greyscale print and a screen reader alike.
              ExcludeSemantics(
                child: Icon(tone.icon, color: tone.color(colors)),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Text(
                  l10n.settingsIdentityNotLinkedTitle,
                  style: AppTypography.of(context).titleSmall,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Text(
            l10n.settingsIdentityNotLinkedMessage,
            style: AppTypography.of(context)
                .bodyMedium
                ?.copyWith(color: colors.onSurfaceMuted),
          ),
          SizedBox(height: spacing.md),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              // Disabled while in flight, with a spinner on the control itself
              // rather than a barrier over the screen.
              onPressed: busy ? null : () => onVerify(),
              child: busy
                  ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.settingsVerifyAction),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopsPanel extends StatelessWidget {
  const _ShopsPanel({
    required this.onAddShop,
    required this.onManage,
    this.onChangeProfile,
    required this.onOpenPortfolio,
    required this.onOpenActivity,
  });

  final Future<void> Function() onAddShop;
  final Future<void> Function() onManage;
  final Future<void> Function()? onChangeProfile;
  final VoidCallback onOpenPortfolio;
  final VoidCallback onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _SettingsSection(
      title: l10n.settingsYourShopsTitle,
      child: Column(
        children: <Widget>[
          SettingsInfoRow(
            icon: Icons.lock_outline,
            title: l10n.settingsSeparateOfflineDataTitle,
          ),
          // The all-shops read, offered next to the switcher because the two
          // questions arrive together: "which shop am I in" and "how are they
          // all doing".
          SettingsNavRow(
            icon: Icons.insights_outlined,
            title: l10n.portfolioOpenAction,
            onTap: onOpenPortfolio,
          ),
          SettingsNavRow(
            icon: Icons.history_outlined,
            title: l10n.activityTitle,
            onTap: onOpenActivity,
          ),
          SettingsNavRow(
            icon: Icons.store_mall_directory_outlined,
            title: l10n.settingsSwitchShopAction,
            onTap: () => onManage(),
          ),
          if (onChangeProfile != null)
            SettingsNavRow(
              icon: Icons.tune_outlined,
              title: l10n.settingsBusinessProfile,
              onTap: onChangeProfile,
            ),
          SettingsNavRow(
            icon: Icons.add_business_outlined,
            title: l10n.settingsAddShopOnDeviceAction,
            onTap: () => onAddShop(),
          ),
        ],
      ),
    );
  }
}

class _StaffPanel extends StatelessWidget {
  const _StaffPanel({
    required this.staff,
    required this.onAdd,
    required this.onResetPin,
    required this.onRemove,
    this.onOpenPermissions,
  });

  final List<Staff> staff;
  final Future<void> Function() onAdd;
  final void Function(Staff) onResetPin;
  final Future<void> Function(Staff) onRemove;
  final VoidCallback? onOpenPermissions;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);

    return _SettingsSection(
      title: l10n.settingsStaffSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (staff.isEmpty)
            // "nobody yet" is its own state, distinct from "none on the backend"
            // and from a failed load: the roster is local, so an empty list is
            // genuinely the whole roster.
            Padding(
              padding: EdgeInsets.all(AppSpacing.of(context).md),
              child: Text(
                l10n.settingsStaffEmpty,
                style: AppTypography.of(context)
                    .bodyMedium
                    ?.copyWith(color: colors.onSurfaceMuted),
              ),
            ),
          for (final Staff s in staff)
            _StaffRow(
              staff: s,
              onResetPin: () => onResetPin(s),
              onRemove: () => onRemove(s),
            ),
          SettingsNavRow(
            icon: Icons.add,
            title: l10n.settingsAddStaffAction,
            onTap: () => onAdd(),
          ),
          if (onOpenPermissions != null)
            SettingsNavRow(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Permissions matrix',
              onTap: onOpenPermissions!,
            ),
        ],
      ),
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({
    required this.staff,
    required this.onResetPin,
    required this.onRemove,
  });

  final Staff staff;
  final VoidCallback onResetPin;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final bool isManager = staff.role == 'manager';

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(staff.name, style: AppTypography.of(context).bodyLarge),
              SizedBox(height: 2),
              Text(
                isManager ? l10n.settingsRoleManager : l10n.settingsRoleCashier,
                style: AppTypography.of(context)
                    .bodySmall
                    ?.copyWith(color: colors.onSurfaceMuted),
              ),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: l10n.settingsStaffActionsTooltip(staff.name),
          child: PopupMenuButton<String>(
            tooltip: l10n.settingsStaffActionsTooltip(staff.name),
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'reset') onResetPin();
              if (value == 'remove') onRemove();
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'reset',
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.lock_reset_outlined, size: 20),
                    SizedBox(width: AppSpacing.of(context).md),
                    Text(l10n.settingsResetPinAction),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'remove',
                child: Text(l10n.settingsRemoveAction),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentsPanel extends StatelessWidget {
  const _PaymentsPanel({
    required this.mpesaEnabled,
    this.mpesaChannelId,
    required this.mpesaChannelType,
    required this.mpesaMerchantNumber,
    required this.saving,
    required this.onToggleMpesa,
  });

  final bool mpesaEnabled;
  final int? mpesaChannelId;
  final String mpesaChannelType;
  final String mpesaMerchantNumber;
  final bool saving;
  final Future<void> Function(bool) onToggleMpesa;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _SettingsSection(
      title: l10n.settingsPaymentMethodsSection,
      child: Column(
        children: <Widget>[
          SettingsInfoRow(
            icon: Icons.payments_outlined,
            title: l10n.settingsCashMethod,
            trailing: l10n.settingsIncluded,
          ),
          SettingsSwitchRow(
            icon: Icons.phone_iphone_outlined,
            title: l10n.settingsMpesaMethod,
            subtitle: mpesaEnabled
                ? '${l10n.settingsMpesaOnSubtitle} · $mpesaChannelType ${mpesaMerchantNumber.isEmpty ? 'number not set' : mpesaMerchantNumber} · Channel ${mpesaChannelId ?? 'not set'}'
                : l10n.settingsMpesaOffSubtitle,
            value: mpesaEnabled,
            enabled: !saving,
            onChanged: (value) => onToggleMpesa(value),
          ),
        ],
      ),
    );
  }
}

class _CashDrawerPanel extends StatelessWidget {
  const _CashDrawerPanel({
    required this.enabled,
    required this.onCashSale,
    required this.pin,
    required this.onMs,
    required this.offMs,
    required this.onChanged,
  });

  final bool enabled;
  final bool onCashSale;
  final int pin;
  final int onMs;
  final int offMs;
  final Future<void> Function(
      {bool? enabled,
      bool? onCashSale,
      int? pin,
      int? onMs,
      int? offMs}) onChanged;

  @override
  Widget build(BuildContext context) => _SettingsSection(
        title: 'Cash drawer',
        child: Column(
          children: [
            SettingsSwitchRow(
              icon: Icons.point_of_sale_outlined,
              title: 'Enable cash drawer',
              subtitle: 'Uses the paired receipt printer drawer port',
              value: enabled,
              onChanged: (value) => onChanged(enabled: value),
            ),
            SettingsSwitchRow(
              icon: Icons.receipt_long_outlined,
              title: 'Open on cash sale',
              subtitle: 'Disabled unless the drawer is enabled',
              value: onCashSale,
              enabled: enabled,
              onChanged: (value) => onChanged(onCashSale: value),
            ),
            ListTile(
              leading: const Icon(Icons.settings_input_component_outlined),
              title: const Text('Drawer connector'),
              subtitle: Text('Pin ${pin + 1} · ${onMs}ms on · ${offMs}ms off'),
              trailing: DropdownButton<int>(
                value: pin,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Pin 1')),
                  DropdownMenuItem(value: 1, child: Text('Pin 2')),
                ],
                onChanged: enabled
                    ? (value) {
                        if (value != null) onChanged(pin: value);
                      }
                    : null,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Pulse timing'),
              subtitle: const Text('Adjust only if the paired drawer needs it'),
              trailing: DropdownButton<int>(
                value: onMs,
                items: const [
                  DropdownMenuItem(value: 50, child: Text('50 / 500 ms')),
                  DropdownMenuItem(value: 100, child: Text('100 / 500 ms')),
                ],
                onChanged: enabled
                    ? (value) {
                        if (value != null) {
                          onChanged(onMs: value, offMs: 500);
                        }
                      }
                    : null,
              ),
            ),
          ],
        ),
      );
}

class _PrinterPanel extends StatelessWidget {
  const _PrinterPanel({
    required this.printer,
    required this.busy,
    required this.onPair,
    required this.onTestPrint,
    required this.onSave,
  });

  final PrinterConfig printer;
  final bool busy;
  final Future<void> Function() onPair;
  final Future<void> Function() onTestPrint;
  final Future<void> Function(PrinterConfig) onSave;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    // STATE, not explanation: what this till can do RIGHT NOW. The switch's
    // position says it, but a shop wondering why no paper came out is looking
    // for a sentence, not for the direction a toggle is pointing.
    //
    // Gated on the ADDRESS, not on `isConfigured` — which also requires
    // `enabled` and so told a printer that was paired but switched off to go and
    // pair one. The two states need opposite responses: "paired but off" is a
    // switch on this screen, "unpaired" is a trip to Bluetooth settings, and the
    // unpaired case renders no switch at all for this line to sit under.
    final String printingState = printer.enabled
        ? l10n.settingsPrintingOnSubtitle
        : l10n.settingsPrintingPairedOffSubtitle;
    return _SettingsSection(
      title: l10n.settingsPrinterSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (printer.macAddress.trim().isNotEmpty) ...<Widget>[
            SettingsInfoRow(
              icon: Icons.bluetooth_connected,
              title: printer.macAddress,
              subtitle: l10n.settingsPaperRoll(printer.paperWidth.mm),
            ),
            SettingsSwitchRow(
              icon: Icons.power_settings_new,
              title: l10n.settingsPrintingEnabled,
              subtitle: printingState,
              value: printer.enabled,
              onChanged: (value) => onSave(printer.copyWith(enabled: value)),
            ),
            SettingsSwitchRow(
              icon: Icons.receipt,
              title: l10n.settingsPrintAfterSale,
              value: printer.printAfterSale,
              onChanged: (value) =>
                  onSave(printer.copyWith(printAfterSale: value)),
            ),
          ],
          SizedBox(height: spacing.sm),
          // The pair button carries the in-flight state itself: a second
          // spinner over the whole screen would say the app froze exactly
          // where it is doing the one thing the owner asked for.
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : () => onPair(),
                  icon: busy
                      ? SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bluetooth_searching),
                  label: Text(printer.macAddress.isEmpty
                      ? l10n.settingsPairAPrinter
                      : l10n.settingsPairAnotherPrinter),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy || !printer.isConfigured
                      ? null
                      : () => onTestPrint(),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.settingsTestPrintAction),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The tax summary line: opens the dedicated tax screen.
class _TaxPanel extends StatelessWidget {
  const _TaxPanel({
    required this.vatRatePercent,
    required this.tin,
    required this.tillCode,
    required this.onOpen,
  });

  final int vatRatePercent;
  final String tin;
  final String tillCode;
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return _SettingsSection(
      title: l10n.taxSettingsTitle,
      child: SettingsNavRow(
        icon: Icons.percent,
        title: l10n.taxSettingsTitle,
        subtitle: tin.isEmpty
            ? l10n.settingsTaxSummary(vatRatePercent, tillCode)
            : l10n.settingsTaxSummaryWithTin(vatRatePercent, tillCode, tin),
        onTap: () => onOpen(),
      ),
    );
  }
}

class _CreditPanel extends StatelessWidget {
  const _CreditPanel({
    required this.enabled,
    required this.defaultLimitMinor,
    required this.limitMode,
    required this.cashiersAllowed,
    required this.reminderTemplate,
    required this.onEdit,
  });

  final bool enabled;
  final int defaultLimitMinor;
  final String limitMode;
  final bool cashiersAllowed;
  final String reminderTemplate;
  final Future<void> Function() onEdit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String summary = enabled
        ? l10n.settingsCreditOnSummary(
            formatMoney(Money.fromMinor(defaultLimitMinor)),
          )
        : l10n.settingsCreditOffSummary;
    return _SettingsSection(
      title: l10n.settingsCreditSection,
      child: SettingsNavRow(
        icon: Icons.account_balance_wallet_outlined,
        title: l10n.settingsCreditSection,
        subtitle: summary,
        onTap: () => onEdit(),
      ),
    );
  }
}

class _DiscountPanel extends StatelessWidget {
  const _DiscountPanel({
    required this.enabled,
    required this.cashierPercent,
    required this.managerPercent,
    required this.onEdit,
  });

  final bool enabled;
  final int cashierPercent;
  final int managerPercent;
  final Future<void> Function() onEdit;

  @override
  Widget build(BuildContext context) => _SettingsSection(
        title: 'Discounts',
        child: SettingsNavRow(
          icon: Icons.sell_outlined,
          title: 'Discounts and price overrides',
          subtitle: enabled
              ? 'Cashier $cashierPercent% · manager $managerPercent%'
              : 'Off — checkout prices stay unchanged',
          onTap: onEdit,
        ),
      );
}

class _ExpenseApprovalPanel extends StatelessWidget {
  const _ExpenseApprovalPanel({required this.limitMinor, required this.onEdit});

  final int limitMinor;
  final Future<void> Function() onEdit;

  @override
  Widget build(BuildContext context) => _SettingsSection(
        title: 'Cash controls',
        child: SettingsNavRow(
          icon: Icons.lock_clock_outlined,
          title: 'Cashier payout approval',
          subtitle:
              'Manager approval above ${formatMoney(Money.fromMinor(limitMinor))}',
          onTap: onEdit,
        ),
      );
}

class _DiscountSettingsForm extends StatefulWidget {
  const _DiscountSettingsForm({
    required this.enabled,
    required this.cashierPercent,
    required this.managerPercent,
    required this.reasonRequired,
    required this.belowCostAllowed,
  });

  final bool enabled;
  final int cashierPercent;
  final int managerPercent;
  final bool reasonRequired;
  final bool belowCostAllowed;

  @override
  State<_DiscountSettingsForm> createState() => _DiscountSettingsFormState();
}

class _DiscountSettingsFormState extends State<_DiscountSettingsForm> {
  late bool enabled = widget.enabled;
  late bool reasonRequired = widget.reasonRequired;
  late bool belowCostAllowed = widget.belowCostAllowed;
  late final TextEditingController cashier =
      TextEditingController(text: '${widget.cashierPercent}');
  late final TextEditingController manager =
      TextEditingController(text: '${widget.managerPercent}');

  @override
  void dispose() {
    cashier.dispose();
    manager.dispose();
    super.dispose();
  }

  void _save() {
    final cashierValue = int.tryParse(cashier.text) ?? 0;
    final managerValue = int.tryParse(manager.text) ?? 0;
    if (cashierValue < 0 ||
        cashierValue > 100 ||
        managerValue < 0 ||
        managerValue > 100) {
      return;
    }
    Navigator.pop(context, <String, Object?>{
      'enabled': enabled,
      'cashierPercent': cashierValue,
      'managerPercent': managerValue,
      'reasonRequired': reasonRequired,
      'belowCostAllowed': belowCostAllowed,
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable discounts'),
              value: enabled,
              onChanged: (value) => setState(() => enabled = value),
            ),
            TextField(
              controller: cashier,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cashier maximum %'),
            ),
            TextField(
              controller: manager,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Manager maximum %'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Require a reason'),
              value: reasonRequired,
              onChanged: (value) => setState(() => reasonRequired = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow discounts below cost'),
              value: belowCostAllowed,
              onChanged: (value) => setState(() => belowCostAllowed = value),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      );
}

class _CreditSettingsSheet extends StatefulWidget {
  const _CreditSettingsSheet({
    required this.enabled,
    required this.defaultLimitMinor,
    required this.limitMode,
    required this.cashiersAllowed,
    required this.reminderTemplate,
  });

  final bool enabled;
  final int defaultLimitMinor;
  final String limitMode;
  final bool cashiersAllowed;
  final String reminderTemplate;

  @override
  State<_CreditSettingsSheet> createState() => _CreditSettingsSheetState();
}

class _CreditSettingsSheetState extends State<_CreditSettingsSheet> {
  late bool _enabled = widget.enabled;
  late bool _cashiersAllowed = widget.cashiersAllowed;
  late String _limitMode = widget.limitMode;
  late final TextEditingController _limit = TextEditingController(
    text: (widget.defaultLimitMinor / 100).toStringAsFixed(2),
  );
  late final TextEditingController _reminder =
      TextEditingController(text: widget.reminderTemplate);

  @override
  void dispose() {
    _limit.dispose();
    _reminder.dispose();
    super.dispose();
  }

  void _save() {
    final double? major = double.tryParse(_limit.text.trim());
    if (major == null || !major.isFinite || major < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context).settingsCreditInvalidLimit)),
      );
      return;
    }
    Navigator.pop(context, <String, Object?>{
      'enabled': _enabled,
      'defaultLimitMinor': Money.fromMajor(major).minorUnits,
      'limitMode': _limitMode,
      'cashiersAllowed': _cashiersAllowed,
      'reminderTemplate': _reminder.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: spacing.lg,
          end: spacing.lg,
          top: spacing.md,
          bottom: MediaQuery.viewInsetsOf(context).bottom + spacing.md,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(l10n.settingsCreditSection,
                  style: AppTypography.of(context).titleLarge),
              SizedBox(height: spacing.md),
              SettingsSwitchRow(
                icon: Icons.account_balance_wallet_outlined,
                title: l10n.settingsCreditEnabledLabel,
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              SizedBox(height: spacing.sm),
              TextField(
                controller: _limit,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.settingsCreditDefaultLimitLabel,
                ),
              ),
              SizedBox(height: spacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _limitMode,
                decoration: InputDecoration(
                  labelText: l10n.settingsCreditLimitModeLabel,
                ),
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'block',
                    child: Text(l10n.settingsCreditLimitBlock),
                  ),
                  DropdownMenuItem(
                    value: 'warn',
                    child: Text(l10n.settingsCreditLimitWarn),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _limitMode = value);
                },
              ),
              SizedBox(height: spacing.sm),
              SettingsSwitchRow(
                icon: Icons.people_outline,
                title: l10n.settingsCreditCashiersLabel,
                value: _cashiersAllowed,
                onChanged: (value) => setState(() => _cashiersAllowed = value),
              ),
              SizedBox(height: spacing.sm),
              TextField(
                controller: _reminder,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: l10n.settingsCreditReminderLabel,
                  helperText: l10n.settingsCreditReminderHelper,
                ),
              ),
              SizedBox(height: spacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l10n.actionCancel),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: Text(l10n.settingsCreditSaveAction),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sync: the one switch and the one button, plus what happened last.
class _SyncPanel extends StatelessWidget {
  const _SyncPanel({
    required this.identityVerified,
    required this.enabled,
    required this.syncing,
    required this.status,
    required this.onToggle,
    required this.onSyncNow,
    this.onOpenIncomingPayments,
    this.onOpenSyncCenter,
  });

  /// True once the emailed code has been presented. Everything that pushes a
  /// shop's data to the backend needs an authoritative online identity, so

  final bool identityVerified;
  final bool enabled;
  final bool syncing;
  final String? status;
  final Future<void> Function(bool) onToggle;
  final Future<void> Function() onSyncNow;
  final VoidCallback? onOpenIncomingPayments;
  final VoidCallback? onOpenSyncCenter;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return _SettingsSection(
      title: l10n.settingsSyncSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsSwitchRow(
            icon: Icons.cloud_sync_outlined,
            title: l10n.settingsAutoBackupSync,
            // The subtitle says which step is missing rather than leaving a
            // dead switch with no explanation: a control that cannot move
            // and does not say why is the one thing on this screen that reads
            // as broken.
            value: identityVerified && enabled,
            enabled: identityVerified,
            onChanged: (value) => onToggle(value),
          ),
          SizedBox(height: spacing.md),
          FilledButton.icon(
            onPressed: syncing ? null : () => onSyncNow(),
            icon: syncing
                ? SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(
                syncing ? l10n.settingsSyncing : l10n.settingsSyncNowAction),
          ),
          if (onOpenIncomingPayments != null) ...<Widget>[
            SizedBox(height: spacing.sm),
            OutlinedButton.icon(
              onPressed: onOpenIncomingPayments,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Incoming M-Pesa payments'),
            ),
          ],
          if (onOpenSyncCenter != null) ...<Widget>[
            SizedBox(height: spacing.sm),
            OutlinedButton.icon(
              onPressed: onOpenSyncCenter,
              icon: const Icon(Icons.sync_problem_outlined),
              label: const Text('Open Sync Center'),
            ),
          ],
          // The result of the last sync, announced rather than left to be seen:
          // "synced just now" is information, and information only the eye can
          // reach is information a screen reader never gets.
          Semantics(
            liveRegion: true,
            child: Text(
              status ?? '',
              style: AppTypography.of(context)
                  .bodyMedium
                  ?.copyWith(color: colors.onSurfaceMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupPanel extends StatelessWidget {
  const _BackupPanel({
    required this.onExportEncrypted,
    required this.onRestoreEncrypted,
    this.onExportFullBackup,
    this.onRestoreFullBackup,
    this.onUploadCloudFullBackup,
    this.onRestoreCloudFullBackup,
    required this.onExport,
    required this.onImport,
    this.onSeedBlackbee,
    required this.onErase,
    required this.onOpenDiagnostics,
    required this.importing,
    required this.importProgress,
  });

  /// Whether an import is running.
  final bool importing;

  /// Where it has got to.
  final ValueListenable<ImportProgress?> importProgress;

  final Future<void> Function() onExportEncrypted;
  final Future<void> Function() onRestoreEncrypted;
  final Future<void> Function()? onExportFullBackup;
  final Future<void> Function()? onRestoreFullBackup;
  final Future<void> Function()? onUploadCloudFullBackup;
  final Future<void> Function()? onRestoreCloudFullBackup;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final VoidCallback? onSeedBlackbee;
  final Future<void> Function() onErase;

  final Future<void> Function() onOpenDiagnostics;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    return _SettingsSection(
      title: l10n.settingsBackupSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Wraps rather than scrolls: at a large text scale these labels
          // become two lines each and a horizontal row would clip them.
          Wrap(
            spacing: spacing.sm,
            runSpacing: spacing.sm,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => onExportEncrypted(),
                child: Text(l10n.settingsExportEncrypted),
              ),
              OutlinedButton(
                onPressed: () => onRestoreEncrypted(),
                child: Text(l10n.settingsRestoreEncrypted),
              ),
              if (onExportFullBackup != null)
                OutlinedButton(
                  onPressed: onExportFullBackup,
                  child: const Text('Back up all shop data'),
                ),
              if (onRestoreFullBackup != null)
                OutlinedButton(
                  onPressed: onRestoreFullBackup,
                  child: const Text('Restore all shop data'),
                ),
              if (onUploadCloudFullBackup != null)
                OutlinedButton.icon(
                  onPressed: onUploadCloudFullBackup,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Upload portable cloud copy'),
                ),
              if (onRestoreCloudFullBackup != null)
                OutlinedButton(
                  onPressed: onRestoreCloudFullBackup,
                  child: const Text('Restore latest cloud copy'),
                ),
              OutlinedButton(
                onPressed: () => onExport(),
                child: Text(l10n.settingsExportInventory),
              ),
              OutlinedButton(
                // Disabled while an import runs: an import that is started
                // twice runs twice.
                onPressed: importing ? null : () => onImport(),
                child: Text(l10n.settingsImportInventory),
              ),
              if (onSeedBlackbee != null)
                OutlinedButton.icon(
                  onPressed: onSeedBlackbee,
                  icon: const Icon(Icons.playlist_add_outlined),
                  label: const Text('Seed BlackBee products'),
                ),
            ],
          ),
          // The import's progress.
          //
          // An import is the longest thing the app does on a tap and the only
          // one with nothing to press while it happens. Without this the
          // button goes quiet for eight seconds and the owner presses it
          // again.
          if (importing) ...<Widget>[
            SizedBox(height: spacing.md),
            _ImportProgressBar(progress: importProgress),
          ],
          SizedBox(height: spacing.sm),
          // Erasure is destructive and separate from the four reversible
          // buttons, so it is a text button in the danger colour rather than a
          // fifth sibling — one mis-tap away from the backups.
          TextButton.icon(
            onPressed: () => onErase(),
            icon: const Icon(Icons.delete_forever),
            style: TextButton.styleFrom(foregroundColor: colors.danger),
            label: Text(l10n.settingsEraseLocalBackupsAction),
          ),
          SizedBox(height: spacing.md),
          // Diagnostics sits with the backups rather than with the analytics:
          // it answers "what broke", which is the same question a backup
          // exists to answer forward.
          SettingsNavRow(
            icon: Icons.health_and_safety_outlined,
            title: l10n.diagnosticsTitle,
            onTap: onOpenDiagnostics,
          ),
        ],
      ),
    );
  }
}

String verificationMessage(
  AppLocalizations l10n,
  VerificationException error,
) =>
    switch (error.failure) {
      VerificationFailure.notConfigured => l10n.settingsVerifyNotConfigured,
      VerificationFailure.identityUnavailable =>
        l10n.settingsVerifyIdentityUnavailable,
      VerificationFailure.emailUnavailable => l10n.settingsVerifyEmailFailed,
      VerificationFailure.expired => l10n.settingsVerifyCodeExpired,
      VerificationFailure.tooManyAttempts => l10n.settingsVerifyCodeBurnt,
      VerificationFailure.tooManyCodes => l10n.settingsVerifyTooManyCodes,
      VerificationFailure.shopSetupRequired => l10n.settingsVerifyShopMissing,
      VerificationFailure.invalidCode => error.attemptsRemaining == null
          ? l10n.settingsVerifyCodeWrong(1)
          : l10n.settingsVerifyCodeWrong(error.attemptsRemaining!),
      VerificationFailure.network => l10n.settingsIdentityLinkFailed,
      VerificationFailure.unknown => l10n.settingsIdentityLinkFailed,
    };
