import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/money.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../services/excel_service.dart';
import '../routing/routes.dart';
import '../services/app_state.dart';
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
import '../theme/typography.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

      final devices = await printer.pairedDevices();
      if (!mounted) return;
      if (devices.isEmpty) {
        _err('No Bluetooth printers are paired with this phone. Pair one from '
            'the phone\'s Bluetooth settings, then come back.');
        return;
      }
      final chosen = await showDialog<PrinterDevice>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(AppLocalizations.of(context).settingsChoosePrinter),
          children: [
            for (final device in devices)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, device),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.print_outlined),
                  title: Text(device.label),
                  subtitle: Text(device.address),
                  trailing: _printer.macAddress == device.address
                      ? const Icon(Icons.check)
                      : null,
                ),
              ),
          ],
        ),
      );
      if (chosen == null || !mounted) return;

      final paired = await printer.pair(chosen.address);
      if (!mounted) return;
      if (!paired && !await printer.isPaired(chosen.address)) {
        _err('Pairing was cancelled. Pair the printer from the phone\'s '
            'Bluetooth settings, then try again.');
        return;
      }

      await _savePrinter(_printer.copyWith(
        macAddress: chosen.address,
        // Turning the shop on here rather than making the owner find a second
        // switch: a printer they just paired is a printer they want used.
        enabled: true,
      ));
      if (!mounted) return;
      _err('${chosen.label} paired.');
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
      final bytes = const EscPosEncoder().encode(
        const ReceiptBuilder(columnBudget: k58mmColumnBudget).build(receipt),
        columnBudget: _printer.paperWidth.columnBudget,
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
    await config.save();
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

  Future<void> _eraseEncryptedBackups() async {
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
  }

  Future<void> _addStaff() async {
    // Read once, before the dialog. A `showDialog` is an async gap, and the
    // screen can be popped underneath it — a lookup after the await would be
    // reading a scope whose element is gone.
    final l10n = AppLocalizations.of(context);
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
      _err('A staff member named "$name" already exists');
      return;
    }
    try {
      await DatabaseHelper.instance.addStaff(Staff(
          name: name,
          role: result['role'] ?? 'cashier',
          pinHash: await AuthService.hashPin(result['pin']!)));
      if (_backendLinked) {
        try {
          await BackendService.syncStaffToBackend();
        } catch (_) {
          _err(l10n.settingsStaffSavedOffline);
        }
      }
      await _load();
    } catch (e) {
      _err("Couldn't add staff — try again.");
    }
  }

  Future<void> _resetPin(Staff s) async {
    final l10n = AppLocalizations.of(context);
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
      _err('PIN reset for ${s.name}');
    } catch (e) {
      _err("Couldn't reset PIN — try again.");
    }
  }

  Future<void> _removeStaff(Staff s) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title:
                  Text(AppLocalizations.of(context).settingsRemoveStaffTitle),
              content: Text(
                  '${s.name} will no longer be able to sign in. Their past sales stay on record.'),
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
      if (_backendLinked) {
        try {
          await BackendService.syncStaffToBackend();
        } catch (_) {
          _err(l10n.settingsStaffRemovedOffline);
        }
      }
      await _load();
    } catch (e) {
      _err("Couldn't remove staff — try again.");
    }
  }

  Future<void> _toggleMpesa(bool value) async {
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
                'This shop needs to be registered with the backend once. Sign '
                'in with the shop identity account; staff continue using local '
                'PINs for the till.',
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
                'Find your channel ID on the payment provider dashboard, '
                'under your wallet/channel settings.',
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
  /// The backend requires the verified token email to match the email captured
  /// during local account creation, so a mismatch is surfaced to the owner
  /// instead of silently linking the wrong identity.
  Future<void> _verifyIdentityOnline() async {
    final state = context.read<AppState>();
    final owner = state.owner!;
    setState(() => _verifyingIdentity = true);
    try {
      await BackendService.linkShopToBackend(
        shopName: owner.shopName,
        ownerName: owner.name,
        email: owner.email,
      );
      await state.loadOwner();
      state.markIdentityLinked();
      if (!mounted) return;
      _err(AppLocalizations.of(context).settingsIdentityLinked);
    } catch (_) {
      if (!mounted) return;
      _err(AppLocalizations.of(context).settingsIdentityLinkFailed);
    } finally {
      if (mounted) setState(() => _verifyingIdentity = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _syncStatus = null;
    });
    final shopName = context.read<AppState>().owner!.shopName;
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
    setState(() {
      _syncing = false;
      _syncStatus = invResult == SyncResult.pushedToSheets &&
              salesResult == SyncResult.pushedToSheets
          ? AppLocalizations.of(context).settingsSyncSheets
          : (invResult == SyncResult.failed || salesResult == SyncResult.failed)
              ? AppLocalizations.of(context).settingsSyncFailed
              : AppLocalizations.of(context).settingsSyncOfflineExcel;
    });
  }

  Future<void> _manageShops() async {
    // Read before the network call: listing shops is an async gap and this screen
    // can be popped underneath it.
    final l10n = AppLocalizations.of(context);
    try {
      final shops = await BackendService.listMyShops();
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title:
                    Text(AppLocalizations.of(context).settingsYourShopsTitle),
                content: SizedBox(
                    width: 380,
                    child: shops.isEmpty
                        ? Text(
                            AppLocalizations.of(context).settingsNoOnlineShops)
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: shops
                                .map((shop) => ListTile(
                                      title: Text(
                                          '${shop['shopName'] ?? 'Unnamed shop'}'),
                                      // Read through a typed cast rather than
                                      // `.toString()` on a map value: the column
                                      // is a name, and formatting whatever is in
                                      // the row would render "null" or a Map to
                                      // a shopkeeper.
                                      subtitle: Text(
                                        shop['role'] as String? ?? '',
                                      ),
                                      trailing: TextButton(
                                        onPressed: () async {
                                          // Read before the first await: switching
                                          // shops tears this whole subtree down.
                                          final l10n =
                                              AppLocalizations.of(context);
                                          try {
                                            await BackendService.switchShop(
                                                shop['tenantId'].toString());
                                            final key = await WorkspaceService
                                                .workspaceForTenant(
                                                    shop['tenantId']
                                                        .toString());
                                            if (key == null) {
                                              throw StateError(
                                                  l10n.settingsShopNotOnDevice);
                                            }
                                            if (dialogContext.mounted) {
                                              Navigator.pop(dialogContext);
                                            }
                                            if (mounted) {
                                              await context
                                                  .read<AppState>()
                                                  .switchWorkspace(key);
                                            }
                                          } catch (e) {
                                            _err(e is StateError
                                                ? e.message
                                                : l10n
                                                    .settingsSwitchShopFailed);
                                          }
                                        },
                                        child: Text(AppLocalizations.of(context)
                                            .settingsSwitchAction),
                                      ),
                                    ))
                                .toList())),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(l10n.settingsCloseAction))
                ],
              ));
    } catch (_) {
      _err(l10n.settingsLoadShopsFailed);
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
    await WorkspaceService.register(workspaceKey: key, shopName: shop);
    await (await SharedPreferences.getInstance()).remove('tenant_id');
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
    await context.read<AppState>().signInAsOwner();
    if (!mounted) return;
    _err('$shop is ready. Your admin account and PIN carried across.');
  }

  @override
  Widget build(BuildContext context) {
    final owner = context.watch<AppState>().owner!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Signed in as shop admin: ${owner.name}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 24),
        if (context.watch<AppState>().identityLinkPending) ...[
          Card(
            color: AppColors.of(context).surfaceSunken,
            child: ListTile(
              leading: Icon(
                Icons.cloud_off_outlined,
                color: AppColors.of(context).warning,
              ),
              title: Text(
                  AppLocalizations.of(context).settingsIdentityNotLinkedTitle),
              subtitle: Text(AppLocalizations.of(context)
                  .settingsIdentityNotLinkedMessage),
              trailing: TextButton(
                onPressed: _verifyingIdentity ? null : _verifyIdentityOnline,
                child: Text(_verifyingIdentity
                    ? AppLocalizations.of(context).settingsVerifying
                    : AppLocalizations.of(context).settingsVerifyAction),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(AppLocalizations.of(context).settingsShopsSection,
            style: Theme.of(context).textTheme.titleMedium),
        Card(
            child: Column(children: [
          ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text(AppLocalizations.of(context)
                  .settingsSeparateOfflineDataTitle),
              subtitle: Text(AppLocalizations.of(context)
                  .settingsSeparateOfflineDataSubtitle)),
          ListTile(
              leading: const Icon(Icons.store_mall_directory_outlined),
              title:
                  Text(AppLocalizations.of(context).settingsSwitchShopAction),
              onTap: _manageShops),
          ListTile(
              leading: const Icon(Icons.add_business_outlined),
              title: Text(
                  AppLocalizations.of(context).settingsAddShopOnDeviceAction),
              onTap: _addShopOnThisDevice),
        ])),
        Text(AppLocalizations.of(context).settingsStaffSection,
            style: Theme.of(context).textTheme.titleMedium),
        Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Text(AppLocalizations.of(context).settingsStaffSectionHelp),
        ),
        Card(
            child: Column(children: [
          ..._staff.map((s) => ListTile(
                title: Text(s.name),
                subtitle: Text(s.role == 'manager'
                    ? AppLocalizations.of(context).settingsRoleManager
                    : AppLocalizations.of(context).settingsRoleCashier),
                trailing: Wrap(spacing: 4, children: [
                  TextButton(
                      onPressed: () => _resetPin(s),
                      child: Text(
                          AppLocalizations.of(context).settingsResetPinAction)),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Remove ${s.name}',
                    onPressed: () => _removeStaff(s),
                  ),
                ]),
              )),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(AppLocalizations.of(context).settingsAddStaffAction),
            onTap: _addStaff,
          ),
        ])),
        const SizedBox(height: 24),
        Text(AppLocalizations.of(context).settingsPaymentMethodsSection,
            style: Theme.of(context).textTheme.titleMedium),
        Card(
            child: Column(children: [
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(AppLocalizations.of(context).settingsCashMethod),
            subtitle:
                Text(AppLocalizations.of(context).settingsCashMethodSubtitle),
            // Read at build time rather than `const`: the style comes from the
            // theme, and a `const` widget cannot call a method.
            trailing: Text(
              AppLocalizations.of(context).settingsIncluded,
              style: AppTypography.of(context).bodySmall,
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.phone_iphone_outlined),
            title: Text(AppLocalizations.of(context).settingsMpesaMethod),
            subtitle: Text(_mpesaEnabled
                ? AppLocalizations.of(context).settingsMpesaOnSubtitle
                : AppLocalizations.of(context).settingsMpesaOffSubtitle),
            value: _mpesaEnabled,
            onChanged: _savingToggle ? null : _toggleMpesa,
          ),
        ])),
        const SizedBox(height: 24),
        Text(AppLocalizations.of(context).settingsPrinterSection,
            style: Theme.of(context).textTheme.titleMedium),
        Card(
            child: Column(children: [
          ListTile(
            leading: Icon(Icons.print_outlined),
            title: Text(AppLocalizations.of(context).settingsPrinterKindTitle),
            subtitle: Text(
                'Pair the printer from this phone\'s Bluetooth settings first, then pair it here.'),
          ),
          if (_printer.macAddress.trim().isNotEmpty)
            ListTile(
              dense: true,
              leading: const Icon(Icons.bluetooth_connected, size: 20),
              title: Text(_printer.macAddress,
                  style: const TextStyle(fontFamily: 'monospace')),
              subtitle: Text('${_printer.paperWidth.mm}mm roll'),
              trailing: TextButton(
                onPressed: _printerBusy ? null : _chooseAndPairPrinter,
                child: Text(AppLocalizations.of(context).settingsChangeAction),
              ),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.power_settings_new),
            title: Text(AppLocalizations.of(context).settingsPrintingEnabled),
            subtitle: Text(_printer.isConfigured
                ? (_printer.enabled
                    ? AppLocalizations.of(context).settingsPrintingOnSubtitle
                    : AppLocalizations.of(context)
                        .settingsPrintingPairedOffSubtitle)
                : AppLocalizations.of(context)
                    .settingsPrintingUnpairedSubtitle),
            value: _printer.enabled,
            onChanged: !_printer.isConfigured
                ? null
                : (value) => _savePrinter(_printer.copyWith(enabled: value)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.receipt),
            title: Text(AppLocalizations.of(context).settingsPrintAfterSale),
            subtitle: Text(
                AppLocalizations.of(context).settingsPrintAfterSaleSubtitle),
            value: _printer.printAfterSale,
            onChanged: _printer.isConfigured
                ? (value) =>
                    _savePrinter(_printer.copyWith(printAfterSale: value))
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _printerBusy ? null : _chooseAndPairPrinter,
                    icon: _printerBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.bluetooth_searching),
                    label: Text(_printer.macAddress.isEmpty
                        ? AppLocalizations.of(context).settingsPairAPrinter
                        : AppLocalizations.of(context)
                            .settingsPairAnotherPrinter),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _printerBusy || !_printer.isConfigured
                        ? null
                        : _testPrint,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                        AppLocalizations.of(context).settingsTestPrintAction),
                  ),
                ),
              ],
            ),
          ),
        ])),
        const SizedBox(height: 24),
        // Tax configuration is now one screen rather than three tiles and two
        // dialogs. It was reachable only behind an edit chevron on a card
        // titled "Tax and receipts", which is how a VAT-registered shop ended up
        // issuing at the default rate without ever having seen the control.
        ListTile(
          leading: const Icon(Icons.percent),
          title: Text(AppLocalizations.of(context).taxSettingsTitle),
          subtitle: Text(
            'VAT $_vatRatePercent%${_tin.isEmpty ? '' : ' · TIN $_tin'}'
            ' · receipts numbered $_tillCode-000001',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openTaxSettings,
        ),
        const SizedBox(height: 24),
        Text(AppLocalizations.of(context).settingsSyncSection,
            style: Theme.of(context).textTheme.titleMedium),
        Card(
            child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
                'When online, sync pushes inventory and sales to a Google Sheet. '
                'With no signal, it saves an Excel file you can share manually instead — nothing is ever blocked by connectivity.'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context).settingsAutoBackupSync),
              subtitle: Text(
                  AppLocalizations.of(context).settingsAutoBackupSyncSubtitle),
              value: _automaticBackupSync,
              onChanged: (value) async {
                await AutoSyncService.setEnabled(value);
                if (mounted) setState(() => _automaticBackupSync = value);
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _syncing ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: Text(_syncing
                  ? AppLocalizations.of(context).settingsSyncing
                  : AppLocalizations.of(context).settingsSyncNowAction),
            ),
            if (_syncStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_syncStatus!),
              ),
          ]),
        )),
        const SizedBox(height: 24),
        Text(AppLocalizations.of(context).settingsBackupSection,
            style: Theme.of(context).textTheme.titleMedium),
        Card(
            child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(AppLocalizations.of(context).settingsBackupHelp),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              OutlinedButton(
                  onPressed: () async {
                    final f = await _excel.exportEncryptedInventory();
                    await _excel.shareFile(f);
                  },
                  child: Text(
                      AppLocalizations.of(context).settingsExportEncrypted)),
              OutlinedButton(
                  onPressed: () async {
                    try {
                      final n = await _excel.importEncryptedInventory();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Restored $n products')));
                    } on FormatException {
                      _err(AppLocalizations.of(context)
                          .settingsInvalidEncryptedBackup);
                    } catch (_) {
                      _err(AppLocalizations.of(context)
                          .settingsDecryptBackupFailed);
                    }
                  },
                  child: Text(
                      AppLocalizations.of(context).settingsRestoreEncrypted)),
              OutlinedButton(
                  onPressed: () async {
                    final f = await _excel.exportInventory();
                    await _excel.shareFile(f);
                  },
                  child: Text(
                      AppLocalizations.of(context).settingsExportInventory)),
              OutlinedButton(
                  onPressed: () async {
                    try {
                      final result = await _excel.importInventory();
                      if (!context.mounted) return;
                      final refused = result.refusedBarcodes;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(refused.isEmpty
                            ? 'Imported ${result.products} products'
                            : 'Imported ${result.products} products. '
                                '${refused.length} barcode(s) were already on '
                                'another product: ${refused.entries.map((e) => '${e.key} (${e.value})').join(', ')}'),
                      ));
                    } on FormatException {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(AppLocalizations.of(context)
                              .settingsInvalidWorkbook)));
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(AppLocalizations.of(context)
                              .settingsImportWorkbookFailed)));
                    }
                  },
                  child: Text(
                      AppLocalizations.of(context).settingsImportInventory)),
            ]),
            const SizedBox(height: 12),
            TextButton.icon(
                onPressed: _eraseEncryptedBackups,
                icon: const Icon(Icons.delete_forever),
                label: Text(AppLocalizations.of(context)
                    .settingsEraseLocalBackupsAction)),
          ]),
        )),
        const SizedBox(height: 32),
        const _AboutFooter(),
      ],
    );
  }
}

/// Version, build, and attribution.
///
/// Last in the list and deliberately quiet. A merchant opening Settings is
/// usually looking for a control, not to read who built the app — but a till
/// that is out of date is worth telling, so the build number is on screen where
/// a support conversation can start from it.
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
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              SimplePosBrand.appName,
              style: AppTypography.of(context).labelLarge,
            ),
            if (_version.isNotEmpty)
              Text(
                '  v$_version',
                style: AppTypography.of(context).labelMedium,
              ),
          ],
        ),
        const SizedBox(height: 2),
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
    return AlertDialog(
      title: Text(widget.pinOnly
          ? 'Reset PIN for ${widget.existingName}'
          : AppLocalizations.of(context).settingsAddStaffAction),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!widget.pinOnly) ...[
          TextField(
              controller: _name,
              decoration: InputDecoration(
                  labelText:
                      AppLocalizations.of(context).settingsStaffNameLabel),
              autofillHints: const [AutofillHints.name]),
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
                  child: Text('${ShopRole.admin.label} (full rights)'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _role = value);
              }),
        ],
        TextField(
            controller: _pin,
            decoration: InputDecoration(
                labelText: AppLocalizations.of(context).settingsPinLabel),
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            autofillHints: const [AutofillHints.oneTimeCode]),
      ]),
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
