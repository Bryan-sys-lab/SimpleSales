import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
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
import '../services/excel_service.dart';
import '../routing/routes.dart';
import '../services/roles.dart';
import '../app_brand.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/backend_service.dart';
import '../services/auto_sync_service.dart';
import '../services/encrypted_backup_service.dart';
import '../services/workspace_service.dart';
import '../services/printer/printer_config.dart';
import '../services/printer/printer_service.dart';
import '../services/printer/receipt_builder.dart';
import '../services/printer/esc_pos_printer.dart';
import '../services/printer/esc_pos_encoder.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../ui/dialogs/verify_identity_dialog.dart';
import '../ui/layout/page.dart';
import '../services/app_update_service.dart';
import '../services/app_release.dart';
import '../services/pin_reset_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SessionRefresh<SettingsScreen> {
  /// The lockout key for the owner's own PIN.
  ///
  /// The same literal the login pad uses for its owner entry, so a wrong PIN
  /// here counts against the counter a wrong PIN there is already spending.
  /// A different key would give this dialog its own private attempt budget.
  final _sync = SyncService();
  final _excel = ExcelService();
  List<Staff> _staff = [];
  bool _syncing = false;
  String? _syncStatus;
  bool _verifyingIdentity = false;
  bool _mpesaEnabled = false;
  bool _backendLinked = false;
  bool _automaticBackupSync = false;
  bool _savingToggle = false;
  PrinterConfig _printer = const PrinterConfig();
  int _vatRatePercent = kDefaultVatRatePercent;
  String _tillCode = '';
  String _tin = '';

  /// Reference count, not a flag: pairing, test printing and the eTIMS upload
  /// can all overlap, and a second boolean would let two of them each claim to
  /// be the only busy one.
  int _printerBusyCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The roster on screen was read for the session that just ended, and staff
  /// management is exactly what a sign-out can change. Drop the list rather
  /// than leave the previous session's roster — with its PIN-reset buttons —
  /// in front of whoever signs in next.
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
    if (!mounted) return;
    setState(() {
      _staff = staff;
      _mpesaEnabled = prefs.getBool('mpesa_enabled_local') ?? false;
      _automaticBackupSync =
          prefs.getBool('automatic_backup_sync_enabled') ?? false;
      _printer = printer;
      _tillCode = tillCode;
      _vatRatePercent = vatRate;
      _tin = tin;
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

  /// Explains a printer failure in terms the owner can act on.
  ///
  /// Takes the catalogue rather than reading one: this is a `static` helper, so
  /// there is no `BuildContext` to read from, and threading a captured context
  /// into a static would be a use-after-dispose waiting for the phone to rotate
  /// mid-pairing.
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
      ));
      if (!mounted) return;
      _err(l10n.settingsPrinterPaired(chosen.label));
    } on PrinterException catch (error) {
      _err(_printerMessage(AppLocalizations.of(context), error.failure));
    } finally {
      _setPrinterBusy(false);
    }
  }

  /// A synthetic receipt, so pairing can be verified before the next customer.
  ///
  /// Uses the real builder and encoder, so what comes out of the printer is
  /// byte-identical to a real receipt — a test print that only says "OK" proves
  /// the link works but tells the owner nothing about the paper width or the
  /// font their till will use all day.
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.accountDeleteConfirmTitle),
        content: Text(l10n.accountDeleteConfirmMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.accountDeleteConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      final report = await AccountDeletionService.deleteAccount(pin: pin);
      if (!mounted) return;
      // The receipt is offered for keeping, because the owner will need to show
      // someone that the account is gone.
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(l10n.accountDeleteDoneTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(report.remoteDeleted
                  ? l10n.accountDeleteDoneRemote
                  : l10n.accountDeleteDoneLocalOnly),
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
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ],
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.pop(context),
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
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title:
                  Text(AppLocalizations.of(context).settingsEraseBackupsTitle),
              content: Text(
                  AppLocalizations.of(context).settingsEraseBackupsMessage),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(AppLocalizations.of(context).actionCancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(AppLocalizations.of(context)
                        .settingsEraseBackupsConfirm)),
              ],
            ));
    if (confirmed != true) return;
    await EncryptedBackupService.cryptographicEraseLocalBackups();
    if (mounted) _err(AppLocalizations.of(context).settingsBackupsErased);
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
          _err(l10n.settingsStaffSavedOffline);
        }
      }
      await _load();
    } catch (e) {
      _err(l10n.settingsAddStaffFailed);
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
      _err(l10n.settingsPinResetFor(s.name));
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
      _err(l10n.settingsResetPinFailed);
    }
  }

  Future<void> _removeStaff(Staff s) async {
    final l10n = AppLocalizations.of(context);
    final state = context.read<AppState>();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title:
                  Text(AppLocalizations.of(context).settingsRemoveStaffTitle),
              content: Text(l10n.settingsRemoveStaffMessage(s.name)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(AppLocalizations.of(context).actionCancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                        AppLocalizations.of(context).settingsRemoveAction)),
              ],
            ));
    if (confirmed != true) return;
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
          _err(l10n.settingsStaffRemovedOffline);
        }
      }
      await _load();
    } catch (e) {
      _err(l10n.settingsRemoveStaffFailed);
    }
  }

  Future<void> _toggleMpesa(bool value) async {
    // Read before the await.
    final AppState state = context.read<AppState>();
    final l10n = AppLocalizations.of(context);
    if (value && !_backendLinked) {
      final linked = await _showLinkBackendDialog();
      if (linked != true) return; // user cancelled — leave the toggle off
    }
    setState(() => _savingToggle = true);
    try {
      if (_backendLinked) {
        await BackendService.setMpesaEnabled(value);
        if (value) {
          await BackendService.syncProductsToBackend();
          await BackendService.syncStaffToBackend();
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('mpesa_enabled_local', value);
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
          _backendLinked = true;
        });
      }
    } catch (e) {
      _err(l10n.settingsMpesaUpdateFailed);
    } finally {
      if (mounted) setState(() => _savingToggle = false);
    }
  }

  Future<bool?> _showLinkBackendDialog() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final channelId = TextEditingController();
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
              const SizedBox(height: 12),
              TextField(
                  controller: channelId,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)
                          .settingsPaymentChannelId),
                  keyboardType: TextInputType.number),
              const SizedBox(height: 4),
              Text(
                l10n.settingsPaymentChannelHint,
                style: AppTypography.of(context).bodySmall,
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
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
                      final cid = int.tryParse(channelId.text.trim());
                      if (cid == null) {
                        setDialogState(() => error =
                            AppLocalizations.of(context)
                                .settingsPaymentChannelIdRequired);
                        return;
                      }
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
                        await BackendService.setMpesaEnabled(true,
                            channelId: cid);
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
    channelId.dispose();
    return result;
  }

  /// Completes the authoritative online link for an offline-created shop.
  ///
  /// Three steps, and each one is a separate failure the owner can act on:
  /// the admin PIN (checked on the device first, so a wrong one never leaves
  /// the phone), the emailed 6-digit code (which is what proves the address),
  /// and the shop the code unlocks. The backend creates the online account
  /// from the email and PIN already captured at setup, so there is no
  /// registration form anywhere in this flow.
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
      _err(AppLocalizations.of(context).settingsIdentityVerified);
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
    setState(() {
      _syncing = true;
      _syncStatus = null;
    });
    // Read before the sync's async gap, and used after it: the audit row has to
    // name the outcome, which is only known once the two syncs have returned.
    final AppState state = context.read<AppState>();
    final AppLocalizations l10n = AppLocalizations.of(context);
    final shopName = state.owner!.shopName;
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
  }

  /// Toggles the automatic backup/sync preference.
  ///
  /// Named rather than an inline closure so the switch's row can stay a dumb
  /// widget with one `onChanged` callback, the same shape as every other
  /// control on this screen.
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
    final state = context.read<AppState>();
    final f = await _excel.exportEncryptedInventory();
    await _excel.shareFile(f);
    // The share has already left the device, so the row says a backup WAS
    // produced — the audit is the last thing standing after the share sheet
    // closes.
    await recordActionAudit(
      state,
      action: AuditAction.backupExported,
      entity: AuditEntity.backup,
      detail: 'encrypted',
    );
  }

  Future<void> _exportInventory() async {
    final state = context.read<AppState>();
    final f = await _excel.exportInventory();
    await _excel.shareFile(f);
    await recordActionAudit(
      state,
      action: AuditAction.backupExported,
      entity: AuditEntity.backup,
      detail: 'plain workbook',
    );
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
      final n = await _excel.importEncryptedInventory();
      if (!mounted) return;
      _err(l10n.settingsRestoredProducts(n));
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
      _err(l10n.settingsInvalidEncryptedBackup);
    } catch (_) {
      if (!mounted) return;
      _err(l10n.settingsDecryptBackupFailed);
    }
  }

  /// Imports a plain workbook, naming any barcode it refused and why.
  Future<void> _importInventory() async {
    final l10n = AppLocalizations.of(context);
    final state = context.read<AppState>();
    try {
      final result = await _excel.importInventory();
      if (!mounted) return;
      final refused = result.refusedBarcodes;
      // One sentence either way. The refusal count is part of the audit row,
      // not just of the snackbar: the snackbar disappears in six seconds, and
      // the question "did this restore drop anything" outlives it.
      final detail = refused.isEmpty
          ? '${result.products} products'
          : '${result.products} products, ${refused.length} barcodes refused';
      if (refused.isEmpty) {
        _err(l10n.settingsImportedProducts(result.products));
      } else {
        // Each code paired with the product that already owns it, so the owner
        // can fix the workbook instead of guessing which rows were skipped.
        // Alphabetical order, as gen-l10n emits the generated parameters:
        // detail, products, refused.
        _err(l10n.settingsImportedProductsWithRefused(
          detail,
          result.products,
          l10n.settingsBarcodesRefusedList(refused.length),
        ));
      }
      await recordActionAudit(
        state,
        action: AuditAction.backupRestored,
        entity: AuditEntity.backup,
        detail: detail,
      );
    } on FormatException {
      if (!mounted) return;
      _err(l10n.settingsInvalidWorkbook);
    } catch (_) {
      if (!mounted) return;
      _err(l10n.settingsImportWorkbookFailed);
    }
  }

  /// The shop switcher.
  ///
  /// Reads the LOCAL REGISTRY, not the backend's shop list. It used to call
  /// `/tenant/shops`, which meant a shop added on this device without a tenant
  /// link was unreachable — its database existed, the app was pointed at it, and
  /// the one screen that changes between them could not see it. The registry is
  /// the only authority on which shops are here, so it is the source of truth;
  /// the backend still contributes the role and the online state where it has
  /// them, but it can no longer be the reason a shop is missing.
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
                          title: Text(shop.shopName),
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

  /// Points the app at [shop] and rebuilds the session around it.
  ///
  /// Separated from the dialog so the dialog's lifetime and the screen's
  /// lifetime are two explicit things: the dialog is popped first, then the
  /// workspace switch tears down and rebuilds the subtree underneath it.
  /// Reading the context after an await is safe here because [messageService]
  /// captures the messaging subtree, which is not the thing being replaced.
  Future<void> _switchToShop(BuildContext dialogContext, LocalShop shop) async {
    final l10n = AppLocalizations.of(context);
    // Captured before the await, and used after it: `_err` needs a live
    // ScaffoldMessenger, which the workspace switch tears down.
    final AppState state = context.read<AppState>();
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
      // Switching tears the session down and reloads from the new shop's own
      // database, so the next screen is that shop's owner, staff and stock.
      await state.switchWorkspace(shop.workspaceKey);
      if (!mounted) return;
      state.signInAsOwner();
      if (!mounted) return;
      _err(l10n.settingsSwitchedToShop(shop.shopName));
    } catch (_) {
      if (!mounted) return;
      _err(l10n.settingsSwitchShopFailed);
    }
  }

  /// Adds a second shop to this device and drops the admin straight into it.
  ///
  /// This used to register a workspace key, drop the tenant link and switch —
  /// and then stop. The new workspace had no owner row, so the router resolved
  /// it as "no shop on this device" and landed on the landing page asking for
  /// an admin to be created again, which is exactly what it looks like from the
  /// owner's side: the app forgot them.
  ///
  /// The fix is not a redirect, it is finishing the job. The new shop gets a
  /// real owner row carrying the current admin's identity *and their existing PIN
  /// hash*, so the same four digits work and no re-authentication is needed.
  Future<void> _addShopOnThisDevice() async {
    final previous = context.read<AppState>().owner;
    final l10n = AppLocalizations.of(context);
    if (previous == null) {
      _err(l10n.settingsSignInBeforeAddingShop);
      return;
    }

    final name = TextEditingController();
    final shop = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(AppLocalizations.of(context).settingsAddShopTitle),
              content: TextField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(
                      labelText:
                          AppLocalizations.of(context).settingsShopNameLabel),
                  autofillHints: const [AutofillHints.organizationName]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppLocalizations.of(context).actionCancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(context, name.text.trim()),
                    child: Text(AppLocalizations.of(context).actionContinue))
              ],
            ));
    name.dispose();
    if (shop == null || shop.isEmpty || !mounted) return;

    final key = 'local-${DateTime.now().microsecondsSinceEpoch}';
    // A brand-new shop registers with NO tenant. That is the point: the new
    // shop is unlinked until its owner verifies it, and clearing the legacy
    // global key stops it inheriting the shop it was created from.
    await WorkspaceService.register(workspaceKey: key, shopName: shop);
    if (!mounted) return;

    // Point the app at the new shop *first*, so the owner row is written into
    // the new shop's database rather than the one being left behind.
    await context.read<AppState>().switchWorkspace(key);
    if (!mounted) return;

    try {
      await DatabaseHelper.instance.createOwner(Owner(
        id: 1,
        name: previous.name,
        // Carried, not retyped. The same person, the same PIN, every shop on
        // this device.
        pinHash: previous.pinHash,
        email: previous.email,
        shopName: shop,
        createdAt: DateTime.now().toIso8601String(),
      ));
    } catch (e) {
      _err(l10n.settingsCreateShopFailed);
      return;
    }

    // Online identity provisioning is opportunistic, exactly as on first-run
    // setup: the shop is fully usable offline and a later attempt can link it.
    try {
      await BackendService.linkShopToBackend(
          shopName: shop, ownerName: previous.name, email: previous.email);
    } catch (_) {
      // Deliberately swallowed. Losing the signal must not lose the shop.
    }

    if (!mounted) return;
    await context.read<AppState>().loadOwner();
    if (!mounted) return;
    context.read<AppState>().signInAsOwner();
    if (!mounted) return;
    _err(l10n.settingsShopReady(shop));
  }

  @override
  Widget build(BuildContext context) {
    // The stateful screen does the async work; this delegates to a widget that
    // takes the loaded values, so the whole presentation can be rendered from a
    // constructed snapshot in a test without a database — the same split the
    // shift screen uses.
    return SettingsPanel(
      identityLinkPending: context.watch<AppState>().identityLinkPending,
      identityVerified: context.watch<AppState>().identityVerified,
      verifyingIdentity: _verifyingIdentity,
      onVerifyIdentity: _verifyIdentityOnline,
      staff: _staff,
      onAddStaff: _addStaff,
      onResetPin: _resetPin,
      onRemoveStaff: _removeStaff,
      mpesaEnabled: _mpesaEnabled,
      savingPaymentToggle: _savingToggle,
      onToggleMpesa: _toggleMpesa,
      printer: _printer,
      printerBusy: _printerBusy,
      onPairPrinter: _chooseAndPairPrinter,
      onTestPrint: _testPrint,
      onSavePrinter: _savePrinter,
      vatRatePercent: _vatRatePercent,
      tin: _tin,
      tillCode: _tillCode,
      onOpenTaxSettings: _openTaxSettings,
      autoSyncEnabled: _automaticBackupSync,
      syncing: _syncing,
      syncStatus: _syncStatus,
      onSetAutoSync: _setAutoSync,
      onSyncNow: _syncNow,
      onExportEncrypted: _exportEncryptedInventory,
      onRestoreEncrypted: _restoreEncryptedInventory,
      onExport: _exportInventory,
      onImport: _importInventory,
      onEraseBackups: _eraseEncryptedBackups,
      onDeleteAccount: _deleteOnlineAccount,
      accountDeleting: _deletingAccount,
      onAddShop: _addShopOnThisDevice,
      onManageShops: _manageShops,
      onOpenPortfolio: () => context.push(Routes.portfolio),
      onOpenActivity: () => context.push(Routes.activity),
    );
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
    required this.mpesaEnabled,
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
    required this.autoSyncEnabled,
    required this.syncing,
    required this.syncStatus,
    required this.onSetAutoSync,
    required this.onSyncNow,
    required this.onExportEncrypted,
    required this.onRestoreEncrypted,
    required this.onExport,
    required this.onImport,
    required this.onEraseBackups,
    required this.onDeleteAccount,
    required this.accountDeleting,
    required this.onAddShop,
    required this.onManageShops,
    required this.onOpenPortfolio,
    required this.onOpenActivity,
  });

  final bool identityLinkPending;
  final bool verifyingIdentity;
  final Future<void> Function() onVerifyIdentity;

  /// Whether the emailed code has been presented and accepted. The until-then
  /// gate on everything that needs an authoritative online identity:
  /// automatic backups, the cross-shop analytics the portfolio screen reads,
  /// and auto-update.
  final bool identityVerified;

  final List<Staff> staff;
  final Future<void> Function() onAddStaff;
  final void Function(Staff) onResetPin;
  final Future<void> Function(Staff) onRemoveStaff;

  final bool mpesaEnabled;
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

  final bool autoSyncEnabled;
  final bool syncing;
  final String? syncStatus;
  final Future<void> Function(bool) onSetAutoSync;
  final Future<void> Function() onSyncNow;

  final Future<void> Function() onExportEncrypted;
  final Future<void> Function() onRestoreEncrypted;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final Future<void> Function() onEraseBackups;

  /// Deletes the online account and erases what this shop held.
  final Future<void> Function() onDeleteAccount;

  /// True while a deletion is running, so the row can be disabled rather than
  /// appearing to have been ignored.
  final bool accountDeleting;

  final Future<void> Function() onAddShop;
  final Future<void> Function() onManageShops;
  final VoidCallback onOpenPortfolio;
  final VoidCallback onOpenActivity;

  @override
  Widget build(BuildContext context) {
    // An unverified identity is the one condition on this screen that is the
    // shop's problem rather than the phone's, so it leads instead of sitting in
    // its own section to be scrolled past.
    return SectionedPage(
      maxContentWidth: 880,
      sections: <Widget>[
        if (identityLinkPending)
          _IdentityBanner(busy: verifyingIdentity, onVerify: onVerifyIdentity),
        _ShopsPanel(
          onAddShop: onAddShop,
          onManage: onManageShops,
          onOpenPortfolio: onOpenPortfolio,
          onOpenActivity: onOpenActivity,
        ),
        _StaffPanel(
          staff: staff,
          onAdd: onAddStaff,
          onResetPin: onResetPin,
          onRemove: onRemoveStaff,
        ),
        _PaymentsPanel(
          mpesaEnabled: mpesaEnabled,
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
        _TaxPanel(
          vatRatePercent: vatRatePercent,
          tin: tin,
          tillCode: tillCode,
          onOpen: onOpenTaxSettings,
        ),
        _SyncPanel(
          identityVerified: identityVerified,
          enabled: autoSyncEnabled,
          syncing: syncing,
          status: syncStatus,
          onToggle: onSetAutoSync,
          onSyncNow: onSyncNow,
        ),
        _BackupPanel(
          onOpenDiagnostics: () => context.push(Routes.diagnostics),
          onExportEncrypted: onExportEncrypted,
          onRestoreEncrypted: onRestoreEncrypted,
          onExport: onExport,
          onImport: onImport,
          onErase: onEraseBackups,
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

  final Future<void> Function() onDeleteAccount;

  /// Opens the owner's account.
  final VoidCallback onOpenProfile;

  /// True while the erasure is running.
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return _SettingsSection(
      title: l10n.settingsAccountSection,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(l10n.settingsProfileRow),
            subtitle: Text(l10n.settingsProfileRowSubtitle),
            onTap: onOpenProfile,
          ),
          // Forgotten-PIN recovery is NOT here, though it belongs to the same
          // idea. The only way to reach this screen is to unlock the till, and
          // unlocking it needs the PIN — so recovery has to be on the login pad
          // (see `_LoginScreenState._forgotPin`), behind nothing.
          ListTile(
            leading: Icon(Icons.delete_forever_outlined,
                color: theme.colorScheme.error),
            title: Text(
              l10n.settingsDeleteAccountAction,
              style: TextStyle(color: theme.colorScheme.error),
            ),
            subtitle: Text(l10n.accountDeleteShortWarning),
            enabled: !deleting,
            onTap: deleting ? null : onDeleteAccount,
          ),
        ],
      ),
    );
  }
}

/// Version, build, and attribution.
///
/// Last in the list and deliberately quiet. A merchant opening Settings is
/// usually looking for a control, not to read who built the app — but a till
/// that is out of date is worth telling, so the build number is on screen where
/// a support conversation can start from it.
/// Checks for a newer build, downloads it, and hands it to the installer.
///
/// The whole reason this screen exists: uninstalling to update would delete the
/// app's private directory, and that directory is the shop's ledger. See
/// `AppUpdateService` for the three conditions that make an in-place update
/// possible at all.
///
/// The channel is an `InheritedWidget`-free lookup: this reads the service from
/// the `Provider` the composition root installs, so there is one channel per app
/// rather than one per screen.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
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
      return l10n.settingsUpdatesFailed(check.reason);
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
          borderRadius: BorderRadius.circular(4),
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

/// The paired-printer picker, which can rescan.
///
/// Its own stateful widget rather than a static `SimpleDialog`, because the
/// device list is a LIVE thing: a printer that was off when the dialog opened is
/// the most common reason the list is short, and the remedy is another scan.
/// A static list means the only way to retry is to close the dialog, and by
/// then the shop has usually given up and gone back to writing receipts by hand.
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
  late Future<List<PrinterDevice>> _devices;

  @override
  void initState() {
    super.initState();
    _devices = widget.printer.pairedDevices();
  }

  void _rescan() {
    setState(() {
      _devices = widget.printer.pairedDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return AlertDialog(
      title: Text(l10n.settingsChoosePrinter),
      contentPadding:
          EdgeInsetsDirectional.only(top: spacing.md, bottom: spacing.sm),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder<List<PrinterDevice>>(
          future: _devices,
          builder:
              (BuildContext context, AsyncSnapshot<List<PrinterDevice>> snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Padding(
                padding: EdgeInsets.all(spacing.md),
                child: Text(l10n.settingsPrinterScanFailed),
              );
            }
            final devices = snap.data ?? const <PrinterDevice>[];
            if (devices.isEmpty) {
              return Padding(
                padding: EdgeInsets.all(spacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l10n.settingsNoPairedPrinters),
                    SizedBox(height: spacing.sm),
                    // Says what to DO, not just what is wrong. The printer is
                    // paired in Android's own Bluetooth settings, and pointing
                    // at that is the difference between a dead end and an
                    // instruction.
                    Text(
                      l10n.settingsNoPairedPrintersHint,
                      style: AppTypography.of(context).bodySmall?.copyWith(
                          color: AppColors.of(context).onSurfaceMuted),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (BuildContext context, int i) {
                final device = devices[i];
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
        SizedBox(height: AppSpacing.of(context).xs),
        Text(
          SimplePosBrand.poweredByTag,
          style: AppTypography.of(context).bodySmall,
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
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.child,
    this.help,
  });

  final String title;
  final String? help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(padding: EdgeInsets.zero, label: title),
        if (help != null) ...<Widget>[
          SizedBox(height: AppSpacing.of(context).xs),
          Text(
            help!,
            // `onSurfaceMuted` at body size: the help line is context for the
            // section, never the reason someone opened the screen.
            style: AppTypography.of(context)
                .bodyMedium
                ?.copyWith(color: AppColors.of(context).onSurfaceMuted),
          ),
        ],
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

/// The identity banner: the one condition on this screen the shop must act on.
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

/// Shops on this device and the linked shop.
class _ShopsPanel extends StatelessWidget {
  const _ShopsPanel({
    required this.onAddShop,
    required this.onManage,
    required this.onOpenPortfolio,
    required this.onOpenActivity,
  });

  final Future<void> Function() onAddShop;
  final Future<void> Function() onManage;
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
            subtitle: l10n.settingsSeparateOfflineDataSubtitle,
          ),
          // The all-shops read, offered next to the switcher because the two
          // questions arrive together: "which shop am I in" and "how are they
          // all doing".
          SettingsNavRow(
            icon: Icons.insights_outlined,
            title: l10n.portfolioOpenAction,
            subtitle: l10n.portfolioOpenSubtitle,
            onTap: onOpenPortfolio,
          ),
          SettingsNavRow(
            icon: Icons.history_outlined,
            title: l10n.activityTitle,
            subtitle: l10n.settingsActivitySubtitle,
            onTap: onOpenActivity,
          ),
          SettingsNavRow(
            icon: Icons.store_mall_directory_outlined,
            title: l10n.settingsSwitchShopAction,
            onTap: () => onManage(),
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

/// The staff roster: who can sign in, and the controls to change that.
class _StaffPanel extends StatelessWidget {
  const _StaffPanel({
    required this.staff,
    required this.onAdd,
    required this.onResetPin,
    required this.onRemove,
  });

  final List<Staff> staff;
  final Future<void> Function() onAdd;
  final void Function(Staff) onResetPin;
  final Future<void> Function(Staff) onRemove;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);

    return _SettingsSection(
      title: l10n.settingsStaffSection,
      help: l10n.settingsStaffSectionHelp,
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
        ],
      ),
    );
  }
}

/// One staff member: the name, the role, and the two things done to them.
///
/// The reset/remove pair was two buttons in a `Wrap` at the end of the row, so
/// they were two sub-44px targets competing with the row's own tap area. They
/// are a menu now — the same shape the inventory row uses, which is why it
/// reads as one system rather than one screen's preference.
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

/// Payment methods: what this till accepts, and the M-Pesa link.
class _PaymentsPanel extends StatelessWidget {
  const _PaymentsPanel({
    required this.mpesaEnabled,
    required this.saving,
    required this.onToggleMpesa,
  });

  final bool mpesaEnabled;
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
            subtitle: l10n.settingsCashMethodSubtitle,
            trailing: l10n.settingsIncluded,
          ),
          SettingsSwitchRow(
            icon: Icons.phone_iphone_outlined,
            title: l10n.settingsMpesaMethod,
            subtitle: mpesaEnabled
                ? l10n.settingsMpesaOnSubtitle
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

/// The printer: pairing, and the two switches that decide what it prints.
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
    final String subtitle = !printer.isConfigured
        ? l10n.settingsPrintingUnpairedSubtitle
        : (printer.enabled
            ? l10n.settingsPrintingOnSubtitle
            : l10n.settingsPrintingPairedOffSubtitle);

    return _SettingsSection(
      title: l10n.settingsPrinterSection,
      help: l10n.settingsPrinterPairHelp,
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
              subtitle: subtitle,
              value: printer.enabled,
              onChanged: (value) => onSave(printer.copyWith(enabled: value)),
            ),
            SettingsSwitchRow(
              icon: Icons.receipt,
              title: l10n.settingsPrintAfterSale,
              subtitle: l10n.settingsPrintAfterSaleSubtitle,
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

/// Sync: the one switch and the one button, plus what happened last.
class _SyncPanel extends StatelessWidget {
  const _SyncPanel({
    required this.identityVerified,
    required this.enabled,
    required this.syncing,
    required this.status,
    required this.onToggle,
    required this.onSyncNow,
  });

  /// True once the emailed code has been presented. Everything that pushes a
  /// shop's data to the backend needs an authoritative online identity, so
  /// until then automatic sync is offered switched off and says why.
  final bool identityVerified;
  final bool enabled;
  final bool syncing;
  final String? status;
  final Future<void> Function(bool) onToggle;
  final Future<void> Function() onSyncNow;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return _SettingsSection(
      title: l10n.settingsSyncSection,
      help: l10n.settingsSyncHelp,
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
            subtitle: identityVerified
                ? l10n.settingsAutoBackupSyncSubtitle
                : l10n.settingsAutoBackupLockedSubtitle,
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

/// Backup and restore: the two directions that matter, plus erasure.
class _BackupPanel extends StatelessWidget {
  const _BackupPanel({
    required this.onExportEncrypted,
    required this.onRestoreEncrypted,
    required this.onExport,
    required this.onImport,
    required this.onErase,
    required this.onOpenDiagnostics,
  });

  final Future<void> Function() onExportEncrypted;
  final Future<void> Function() onRestoreEncrypted;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final Future<void> Function() onErase;

  /// Where the phone's failure log lives.
  final Future<void> Function() onOpenDiagnostics;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);

    return _SettingsSection(
      title: l10n.settingsBackupSection,
      help: l10n.settingsBackupHelp,
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
              OutlinedButton(
                onPressed: () => onExport(),
                child: Text(l10n.settingsExportInventory),
              ),
              OutlinedButton(
                onPressed: () => onImport(),
                child: Text(l10n.settingsImportInventory),
              ),
            ],
          ),
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
            subtitle: l10n.settingsDiagnosticsHelp,
            onTap: onOpenDiagnostics,
          ),
        ],
      ),
    );
  }
}

/// The sentence a verification failure is worth.
///
/// A free function rather than a method on the screen: the copy is a locale
/// decision, and a test can walk the whole taxonomy without building a
/// SettingsScreen to do it.
///
/// Every branch ends in something the owner can act on — a new code, a
/// resend, a wait, or a retry when the signal comes back. The branch that
/// cannot is [VerificationFailure.unknown], which deliberately falls back to
/// the generic link failure: an unrecognised cause is not a sentence worth
/// inventing.
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
