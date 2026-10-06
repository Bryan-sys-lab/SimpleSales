import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_brand.dart';
import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/app_state.dart';
import '../services/etims/etims_service.dart';
import '../services/workspace_service.dart';
import '../services/printer/receipt_builder.dart';
import '../theme/app_colors.dart';
import '../theme/typography.dart';
import '../utils/money.dart';
import '../services/backend_service.dart';

/// Tax and receipt-numbering configuration.
///
/// A screen rather than another dialog inside Settings, because this is the one
/// place a shop sets the figures that appear on a legal document. It was buried
/// two taps deep behind an edit chevron on a card titled "Tax and receipts",
/// which is how a VAT-registered shop ended up issuing receipts at the default
/// rate without ever having seen the control.
///
/// Everything here is owner-only. Managers and cashiers never see the tab: the
/// VAT rate and the TIN are shop-level financial configuration, and a cashier
/// seeing them is a needless disclosure even though they are not secret.
class TaxSettingsScreen extends StatefulWidget {
  const TaxSettingsScreen({super.key});

  @override
  State<TaxSettingsScreen> createState() => _TaxSettingsScreenState();
}

class _TaxSettingsScreenState extends State<TaxSettingsScreen> {
  int _vatRatePercent = kDefaultVatRatePercent;
  bool _pricesIncludeVat = true;
  bool _etimsEnabled = false;
  String _tillCode = '';
  String _tin = '';
  String _etimsDeviceId = '';
  bool _loading = true;
  bool _saving = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final vatRate = await db.getVatRatePercent();
    final tillCode = await db.getTillCode();
    final tin = (await db.getSetting(DatabaseHelper.settingTin)) ?? '';
    final device =
        (await db.getSetting(DatabaseHelper.settingEtimsDeviceId)) ?? '';
    final prefs = await SharedPreferences.getInstance();
    final includesVat = prefs.getBool(_pricesIncludeVatKey) ?? true;
    final etimsOn = prefs.getBool(EtimsService.etimsEnabledPrefKey) ?? false;
    if (!mounted) return;
    setState(() {
      _etimsEnabled = etimsOn;
      _vatRatePercent = vatRate;
      _tillCode = tillCode;
      _tin = tin;
      _etimsDeviceId = device;
      _pricesIncludeVat = includesVat;
      _loading = false;
    });
  }

  static const _pricesIncludeVatKey = 'prices_include_vat';

  /// Turns eTIMS issuance on or off.
  ///
  /// Refuses to turn it on before a TIN exists. A shop that enables this with
  /// no PIN would queue every sale into an offline KRA queue that can never
  /// drain, and the owner would find out days later from an unissued invoice
  /// rather than from this screen.
  Future<void> _toggleEtims(bool value) async {
    if (value && _tin.trim().isEmpty) {
      setState(() {
        _message = AppLocalizations.of(context).taxSettingsRegisterPinFirst;
        _messageIsError = true;
      });
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      // Push to the backend first. If that fails, the till must not believe it
      // is filing receipts when the shop's authoritative flag says otherwise.
      final linked = await BackendService.isBackendLinked;
      if (linked) await BackendService.setEtimsEnabled(value);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(EtimsService.etimsEnabledPrefKey, value);
      if (!mounted) return;
      setState(() {
        _etimsEnabled = value;
        _message = value
            ? AppLocalizations.of(context).taxSettingsEtimsOn
            : AppLocalizations.of(context).taxSettingsEtimsOff;
        _messageIsError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = AppLocalizations.of(context).taxSettingsEtimsUpdateFailed;
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Persists the whole screen in one go.
  ///
  /// One save rather than per-field writes because these values interact: a VAT
  /// rate change with a stale till code in the same gesture is not a state any
  /// receipt should ever be issued from.
  Future<void> _save({
    int? vatRatePercent,
    bool? pricesIncludeVat,
    String? tillCode,
    String? tin,
  }) async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final db = DatabaseHelper.instance;
      if (vatRatePercent != null) await db.setVatRatePercent(vatRatePercent);
      if (tillCode != null) await db.setTillCode(tillCode);
      if (tin != null) await db.setSetting(DatabaseHelper.settingTin, tin);
      if (pricesIncludeVat != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_pricesIncludeVatKey, pricesIncludeVat);
      }
      if (!mounted) return;
      setState(() {
        if (vatRatePercent != null) _vatRatePercent = vatRatePercent;
        if (tillCode != null) _tillCode = tillCode;
        if (tin != null) _tin = tin;
        if (pricesIncludeVat != null) _pricesIncludeVat = pricesIncludeVat;
        _message = AppLocalizations.of(context).taxSettingsSaved;
        _messageIsError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = "Couldn't save. Check the phone has storage free.";
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// What a KSh 100 line will look like, so the rate is not an abstraction.
  String _workedExample(int rate) {
    final gross = Money.fromMajor(100);
    final vat = vatComponentOf(gross, ratePercent: rate);
    return 'A KSh 100 sale carries KSh ${vat.asMajor.toStringAsFixed(2)} VAT, '
        'leaving KSh ${(gross - vat).asMajor.toStringAsFixed(2)} net.';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isAdmin) {
      // Defence in depth. Settings does not show the tab to a non-admin, but a
      // screen that mints a TIN should not depend on that alone.
      return Scaffold(
        appBar:
            AppBar(title: Text(AppLocalizations.of(context).taxSettingsTitle)),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(AppLocalizations.of(context).taxSettingsAdminOnly),
          ),
        ),
      );
    }

    return Scaffold(
      appBar:
          AppBar(title: Text(AppLocalizations.of(context).taxSettingsTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(AppLocalizations.of(context).taxSettingsVatSection),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: Text('VAT rate: $_vatRatePercent%'),
                        subtitle: Text(_vatRatePercent == 0
                            ? AppLocalizations.of(context).taxSettingsVatExempt
                            : _workedExample(_vatRatePercent)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _vatRatePercent.toDouble(),
                                // 0 to 25 in whole steps. Kenya's standard is
                                // 16; 0 means exempt. Anything above 25 is not
                                // a rate any real Kenyan shop faces and would
                                // only produce absurd VAT figures.
                                min: 0,
                                max: 25,
                                divisions: 25,
                                label: AppLocalizations.of(context)
                                    .taxVatRatePercent(_vatRatePercent),
                                // Announced, because a slider's value is
                                // invisible to a screen reader otherwise.
                                semanticFormatterCallback: (v) =>
                                    'VAT rate ${v.round()} percent',
                                onChanged: _saving
                                    ? null
                                    : (v) => setState(
                                        () => _vatRatePercent = v.round()),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _saving
                                  ? null
                                  : () =>
                                      _save(vatRatePercent: _vatRatePercent),
                              child: Text(AppLocalizations.of(context)
                                  .taxSettingsApplyAction),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 24),
                      SwitchListTile(
                        title: Text(AppLocalizations.of(context)
                            .taxSettingsPricesIncludeVat),
                        subtitle: const Text(
                          'On: you type the shelf price and VAT is extracted from '
                          'it. Off: you type the net price and VAT is added on top.',
                        ),
                        value: _pricesIncludeVat,
                        onChanged:
                            _saving ? null : (v) => _save(pricesIncludeVat: v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _section(AppLocalizations.of(context)
                    .taxSettingsReceiptNumberingSection),
                Card(
                  child: ListTile(
                    title:
                        Text(AppLocalizations.of(context).taxSettingsTillCode),
                    subtitle: Text(
                      'Receipts are numbered $_tillCode-000001, and KRA needs '
                      'that number to match the sequence it has on file. Give '
                      'each till its own code.',
                    ),
                    trailing: TextButton(
                      onPressed: _saving ? null : _editTillCode,
                      child: Text(
                          AppLocalizations.of(context).taxSettingsChangeAction),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _section(AppLocalizations.of(context).taxSettingsEtimsSection),
                Card(
                  child: Column(
                    children: [
                      // The master switch lives here rather than in Settings.
                      // It is tax configuration, it is owner-only like the rest
                      // of this screen, and turning it on with no TIN registered
                      // would queue every sale against a shop that can never
                      // issue a receipt — so the two belong side by side where
                      // the dependency is visible.
                      SwitchListTile(
                        secondary: const Icon(Icons.receipt_long_outlined),
                        title: Text(AppLocalizations.of(context)
                            .taxSettingsIssueEtimsTitle),
                        subtitle: Text(_etimsEnabled
                            ? 'On — every sale is filed with KRA. Sales keep '
                                'working with no signal; receipts upload as soon '
                                'as there is a connection.'
                            : 'Off — sales are recorded but no tax invoice is '
                                'issued. Turn this on once a TIN is registered.'),
                        value: _etimsEnabled,
                        onChanged: _saving ? null : _toggleEtims,
                      ),
                      if (_etimsEnabled) ...[
                        const Divider(height: 1),
                      ],
                      ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: Text(_tin.isEmpty
                            ? AppLocalizations.of(context)
                                .taxSettingsTinNotRegistered
                            : AppLocalizations.of(context)
                                .taxTaxpayerPIN(_tin)),
                        subtitle: Text(_tin.isEmpty
                            ? 'Receipts cannot be issued until this shop\'s KRA '
                                'PIN is registered. Until then, sales are '
                                'recorded but no tax invoice is issued.'
                            : AppLocalizations.of(context)
                                .taxSettingsTinRegisteredHelp),
                        trailing: TextButton(
                          onPressed: _saving ? null : _editTin,
                          child: Text(_tin.isEmpty
                              ? AppLocalizations.of(context)
                                  .taxSettingsRegisterAction
                              : AppLocalizations.of(context)
                                  .taxSettingsChangeAction),
                        ),
                      ),
                      if (_etimsDeviceId.isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.devices_outlined),
                          title: Text(AppLocalizations.of(context)
                              .taxSettingsRegisteredDevice),
                          subtitle: Text(_etimsDeviceId),
                        ),
                      ListTile(
                        leading: const Icon(Icons.cloud_upload_outlined),
                        title: Text(AppLocalizations.of(context)
                            .taxSettingsWaitForReceipts),
                        subtitle: Text(
                          'Queued automatically after every sale while online. '
                          'Sales never wait for it.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _saving ? null : _refreshQueue,
                      ),
                    ],
                  ),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _message!,
                      style: TextStyle(
                        // Both tones from the same slot family, so the
                        // success/error pair cannot drift apart as they did when
                        // one came from the ColorScheme and one from a literal.
                        color: _messageIsError
                            ? AppColors.of(context).danger
                            : AppColors.of(context).success,
                      ),
                    ),
                  ),
                const SizedBox(height: 32),
                Center(
                  child: Text(
                    SimplePosBrand.poweredByTag,
                    style: AppTypography.of(context).bodySmall,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 8, start: 4),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Future<void> _editTillCode() async {
    final controller = TextEditingController(text: _tillCode);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).taxSettingsTillCode),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Not `const`: the style comes from the theme, and a `const`
              // widget cannot call `AppTypography.of(context)`.
              Text(
                'Letters and digits only. Every till in a shop needs its own '
                'code, because KRA rejects two tills issuing the same receipt '
                'number.',
                style: AppTypography.of(context).bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                ],
                decoration: InputDecoration(
                    labelText:
                        AppLocalizations.of(context).taxSettingsTillCode),
              ),
              if (error != null)
                Text(error!,
                    style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim().toUpperCase();
                if (value.isEmpty) {
                  setDialogState(() => error =
                      AppLocalizations.of(context).taxSettingsTillCodeRequired);
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: Text(AppLocalizations.of(context).inventorySaveAction),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    await _save(tillCode: result);
  }

  Future<void> _editTin() async {
    final controller = TextEditingController(text: _tin);
    String? error;
    var submitting = false;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).taxSettingsKraPinTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enter the PIN exactly as printed on this shop\'s KRA '
                  'certificate, including the P0 prefix. A PIN issued to the '
                  'wrong business puts invoices on someone else\'s return.',
                  style: AppTypography.of(context).bodyMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  ],
                  decoration: InputDecoration(
                      labelText:
                          AppLocalizations.of(context).taxSettingsTinLabel),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!,
                        style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final value = controller.text.trim().toUpperCase();
                      if (value.length < 4) {
                        setDialogState(() => error =
                            AppLocalizations.of(context)
                                .taxSettingsTinTooShort);
                        return;
                      }
                      setDialogState(() {
                        submitting = true;
                        error = null;
                      });
                      try {
                        final deviceId = await _deviceIdentifier();
                        await BackendService.registerEtimsDevice(
                            tin: value, deviceId: deviceId);
                        await DatabaseHelper.instance
                            .setSetting(DatabaseHelper.settingTin, value);
                        await DatabaseHelper.instance.setSetting(
                            DatabaseHelper.settingEtimsDeviceId, deviceId);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, value);
                        }
                      } catch (_) {
                        setDialogState(() {
                          submitting = false;
                          error = AppLocalizations.of(context)
                              .taxSettingsKraUnreachable;
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      AppLocalizations.of(context).taxSettingsRegisterAction),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    await _save(tin: result);
  }

  /// Uploads anything waiting and reports what happened.
  Future<void> _refreshQueue() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final outcome = await EtimsService().flushPending();
      if (!mounted) return;
      setState(() {
        _message = EtimsService.describeResult(outcome);
        _messageIsError = outcome.remaining > 0 && outcome.uploaded == 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = AppLocalizations.of(context).taxSettingsKraUnreachableRetry;
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// A stable identifier for this till's eTIMS device.
  ///
  /// Derived from the workspace rather than random per launch: KRA treats the
  /// device as a registered installation, and an identifier that changed every
  /// launch would look like a new device every day.
  Future<String> _deviceIdentifier() async {
    final workspace = await WorkspaceService.activeWorkspaceKey();
    final digest = sha256.convert(utf8.encode('simple-pos-etims:$workspace'));
    return digest.toString().substring(0, 16).toUpperCase();
  }
}
