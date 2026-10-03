import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../services/excel_service.dart';
import '../services/app_state.dart';
import '../services/backend_service.dart';
import '../services/auto_sync_service.dart';
import '../services/encrypted_backup_service.dart';
import '../services/workspace_service.dart';
import '../theme/app_theme.dart';

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
  bool _etimsEnabled = false;
  bool _backendLinked = false;
  bool _automaticBackupSync = false;
  bool _savingToggle = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final staff = await DatabaseHelper.instance.getStaff();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _staff = staff;
      _mpesaEnabled = prefs.getBool('mpesa_enabled_local') ?? false;
      _etimsEnabled = prefs.getBool('etims_enabled_local') ?? false;
      _automaticBackupSync =
          prefs.getBool('automatic_backup_sync_enabled') ?? false;
    });
    _backendLinked = await BackendService.isBackendLinked;
    if (mounted) setState(() {});
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
              title: const Text('Erase encrypted backups?'),
              content: const Text(
                  'This permanently removes this phone’s backup key and encrypted backup files. Copies already shared to another device or cloud storage are not erased.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Erase local backups')),
              ],
            ));
    if (confirmed != true) return;
    await EncryptedBackupService.cryptographicEraseLocalBackups();
    if (mounted) _err('Local encrypted backups and their key were erased.');
  }

  Future<void> _addStaff() async {
    final result = await showDialog<Map<String, String>>(
        context: context, builder: (_) => const _StaffDialog());
    if (result == null) return;
    final name = (result['name'] ?? '').trim();
    if (name.isEmpty) {
      _err('Enter a staff name');
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
          _err(
              'Cashier saved offline. It will be linked to the backend on the next successful sync.');
        }
      }
      await _load();
    } catch (e) {
      _err("Couldn't add staff — try again.");
    }
  }

  Future<void> _resetPin(Staff s) async {
    final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => _StaffDialog(existingName: s.name, pinOnly: true));
    if (result == null) return;
    if (!RegExp(r'^\d{4}$').hasMatch(result['pin'] ?? '')) {
      _err('PIN must be exactly 4 digits');
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
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Remove staff member?'),
              content: Text(
                  '${s.name} will no longer be able to sign in. Their past sales stay on record.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Remove')),
              ],
            ));
    if (confirmed != true) return;
    try {
      await DatabaseHelper.instance.deleteStaffWithTombstone(s);
      if (_backendLinked) {
        try {
          await BackendService.syncStaffToBackend();
        } catch (_) {
          _err(
              'Cashier removed locally. Backend access will be updated on the next successful sync.');
        }
      }
      await _load();
    } catch (e) {
      _err("Couldn't remove staff — try again.");
    }
  }

  Future<void> _toggleMpesa(bool value) async {
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
      _err(
          "Couldn't update M-Pesa setting — check your connection and try again.");
    } finally {
      if (mounted) setState(() => _savingToggle = false);
    }
  }

  Future<void> _toggleEtims(bool value) async {
    setState(() => _savingToggle = true);
    try {
      if (_backendLinked) await BackendService.setEtimsEnabled(value);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('etims_enabled_local', value);
      if (mounted) setState(() => _etimsEnabled = value);
    } catch (e) {
      _err(
          "Couldn't update eTIMS setting — check your connection and try again.");
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
          title: const Text('Connect M-Pesa (via PayHero)'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                'This shop needs to be registered with the backend once. Sign in with the shop identity account; '
                'staff continue using local PINs for the till.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: channelId,
                  decoration:
                      const InputDecoration(labelText: 'PayHero channel ID'),
                  keyboardType: TextInputType.number),
              const SizedBox(height: 4),
              const Text(
                  'Find your channel ID on your PayHero dashboard, under your wallet/channel settings.',
                  style: TextStyle(fontSize: 12, color: DukaColors.mutedInk)),
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
                child: const Text('Cancel')),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final cid = int.tryParse(channelId.text.trim());
                      if (cid == null) {
                        setDialogState(
                            () => error = 'Enter a numeric PayHero channel ID');
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
                          error =
                              "Couldn't connect. Check the identity login and internet connection.";
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Connect'),
            ),
          ],
        );
      }),
    );
    channelId.dispose();
    return result;
  }

  /// Completes the authoritative Keycloak link for an offline-created shop.
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
      _err('Online identity linked. M-Pesa and analytics are now available.');
    } catch (_) {
      if (!mounted) return;
      _err(
          'Could not link your online account. Check your connection and sign in with the same email you entered during setup.');
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
          ? 'Synced to Google Sheets just now.'
          : (invResult == SyncResult.failed || salesResult == SyncResult.failed)
              ? 'Sync failed — try again when you have signal.'
              : 'No internet — saved an Excel file instead. Share it from the prompt that opened.';
    });
  }

  Future<void> _manageShops() async {
    try {
      final shops = await BackendService.listMyShops();
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: const Text('Your shops'),
                content: SizedBox(
                    width: 380,
                    child: shops.isEmpty
                        ? const Text(
                            'No online shops are linked to this identity yet.')
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: shops
                                .map((shop) => ListTile(
                                      title: Text(
                                          '${shop['shopName'] ?? 'Unnamed shop'}'),
                                      subtitle:
                                          Text(shop['role']?.toString() ?? ''),
                                      trailing: TextButton(
                                        onPressed: () async {
                                          try {
                                            await BackendService.switchShop(
                                                shop['tenantId'].toString());
                                            final key = await WorkspaceService
                                                .workspaceForTenant(
                                                    shop['tenantId']
                                                        .toString());
                                            if (key == null) {
                                              throw StateError(
                                                  'Set this shop up on this device first');
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
                                                : 'Could not switch shops');
                                          }
                                        },
                                        child: const Text('Switch'),
                                      ),
                                    ))
                                .toList())),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close'))
                ],
              ));
    } catch (_) {
      _err('Could not load shops. Connect to the internet and try again.');
    }
  }

  Future<void> _addShopOnThisDevice() async {
    final name = TextEditingController();
    final shop = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Add another shop'),
              content: TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Shop name'),
                  autofillHints: const [AutofillHints.organizationName]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, name.text.trim()),
                    child: const Text('Continue'))
              ],
            ));
    name.dispose();
    if (shop == null || shop.isEmpty) return;
    final key = 'local-${DateTime.now().microsecondsSinceEpoch}';
    await WorkspaceService.register(workspaceKey: key, shopName: shop);
    await (await SharedPreferences.getInstance()).remove('tenant_id');
    if (!mounted) return;
    await context.read<AppState>().switchWorkspace(key);
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
            color: DukaColors.surfaceWarm,
            child: ListTile(
              leading: const Icon(Icons.cloud_off_outlined,
                  color: DukaColors.warning),
              title: const Text('Online identity not linked yet'),
              subtitle: const Text(
                  'Selling works fully offline. Connect to the internet and sign in with your Keycloak account to enable M-Pesa and analytics.'),
              trailing: TextButton(
                onPressed: _verifyingIdentity ? null : _verifyIdentityOnline,
                child: Text(_verifyingIdentity ? 'Verifying…' : 'Verify'),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text('Shops and offline workspaces',
            style: Theme.of(context).textTheme.titleMedium),
        Card(
            child: Column(children: [
          const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Each shop has separate offline data'),
              subtitle: Text(
                  'Sales, stock, staff, and backups cannot mix between shops on this device.')),
          ListTile(
              leading: const Icon(Icons.store_mall_directory_outlined),
              title: const Text('Switch linked shop'),
              onTap: _manageShops),
          ListTile(
              leading: const Icon(Icons.add_business_outlined),
              title: const Text('Add another shop on this device'),
              onTap: _addShopOnThisDevice),
        ])),
        Text('Managers and cashiers',
            style: Theme.of(context).textTheme.titleMedium),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
              'The shop admin creates and disables manager and cashier profiles. Their local PIN is the offline till unlock; the same profile is synchronized to Keycloak-backed analytics when online.'),
        ),
        Card(
            child: Column(children: [
          ..._staff.map((s) => ListTile(
                title: Text(s.name),
                subtitle: Text(s.role == 'manager' ? 'Manager' : 'Cashier'),
                trailing: Wrap(spacing: 4, children: [
                  TextButton(
                      onPressed: () => _resetPin(s),
                      child: const Text('Reset PIN')),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Remove ${s.name}',
                    onPressed: () => _removeStaff(s),
                  ),
                ]),
              )),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add staff'),
            onTap: _addStaff,
          ),
        ])),
        const SizedBox(height: 24),
        Text('Payment methods', style: Theme.of(context).textTheme.titleMedium),
        Card(
            child: Column(children: [
          const ListTile(
            leading: Icon(Icons.payments_outlined),
            title: Text('Cash'),
            subtitle: Text('Always available — works fully offline.'),
            trailing:
                Text('Included', style: TextStyle(color: DukaColors.mutedInk)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.phone_iphone_outlined),
            title: const Text('M-Pesa (via PayHero)'),
            subtitle: Text(_mpesaEnabled
                ? 'Included — customers can pay by M-Pesa STK push. Requires internet at checkout.'
                : 'Excluded — turn on to accept M-Pesa. Requires a one-time backend connection and a PayHero account.'),
            value: _mpesaEnabled,
            onChanged: _savingToggle ? null : _toggleMpesa,
          ),
        ])),
        const SizedBox(height: 24),
        Text('Tax compliance', style: Theme.of(context).textTheme.titleMedium),
        Card(
            child: SwitchListTile(
          secondary: const Icon(Icons.receipt_long_outlined),
          title: const Text('eTIMS record-keeping'),
          subtitle: Text(_etimsEnabled
              ? 'Included — sales are flagged for eTIMS follow-up. This does NOT yet submit invoices to KRA — see the note below.'
              : 'Excluded. Turn on only as a reminder flag; this app is not yet KRA-eTIMS certified.'),
          value: _etimsEnabled,
          onChanged: _savingToggle ? null : _toggleEtims,
        )),
        if (_etimsEnabled)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
            child: Text(
              'Important: this toggle does not connect to KRA. If this shop is VAT-registered, real tax '
              'invoices must currently be issued through KRA\'s own eTIMS app alongside this one — see the '
              'go-live checklist for what a real integration would require.',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 24),
        Text('Sync — Google Sheets & Excel',
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
              title: const Text('Automatic backup and online sync'),
              subtitle: const Text(
                  'Opt in to retry online sync and save a local inventory backup while the app is open.'),
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
              label: Text(_syncing ? 'Syncing…' : 'Sync now'),
            ),
            if (_syncStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_syncStatus!),
              ),
          ]),
        )),
        const SizedBox(height: 24),
        Text('Backup', style: Theme.of(context).textTheme.titleMedium),
        Card(
            child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
                'Export a full backup regularly, and keep a copy somewhere safe off this phone.'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              OutlinedButton(
                  onPressed: () async {
                    final f = await _excel.exportEncryptedInventory();
                    await _excel.shareFile(f);
                  },
                  child: const Text('Export encrypted backup (.duka)')),
              OutlinedButton(
                  onPressed: () async {
                    try {
                      final n = await _excel.importEncryptedInventory();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Restored $n products')));
                    } on FormatException {
                      _err(
                          'That encrypted backup is invalid or belongs to another installation.');
                    } catch (_) {
                      _err('Couldn’t decrypt the backup.');
                    }
                  },
                  child: const Text('Restore encrypted backup')),
              OutlinedButton(
                  onPressed: () async {
                    final f = await _excel.exportInventory();
                    await _excel.shareFile(f);
                  },
                  child: const Text('Export inventory (.xlsx)')),
              OutlinedButton(
                  onPressed: () async {
                    try {
                      final n = await _excel.importInventory();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Imported $n products')));
                    } on FormatException {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'That workbook has invalid inventory data. No products were imported.')));
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Couldn’t import the workbook. Check the file and try again.')));
                    }
                  },
                  child: const Text('Import inventory (.xlsx)')),
            ]),
            const SizedBox(height: 12),
            TextButton.icon(
                onPressed: _eraseEncryptedBackups,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Erase local encrypted backups')),
          ]),
        )),
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
          : 'Add staff'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!widget.pinOnly) ...[
          TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              autofillHints: const [AutofillHints.name]),
          DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                DropdownMenuItem(value: 'manager', child: Text('Manager')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _role = value);
              }),
        ],
        TextField(
            controller: _pin,
            decoration: const InputDecoration(labelText: '4-digit PIN'),
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            autofillHints: const [AutofillHints.oneTimeCode]),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'name': widget.existingName ?? _name.text.trim(),
            'pin': _pin.text,
            'role': _role
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
