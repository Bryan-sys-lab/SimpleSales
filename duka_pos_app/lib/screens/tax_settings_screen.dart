import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/audit_log.dart';
import '../models/tax_entity.dart';
import '../services/app_state.dart';
import '../services/audit_actor.dart';
import '../services/etims/etims_service.dart';
import '../services/printer/receipt_builder.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/brand/nerva_wordmark.dart';
import '../ui/components/controls.dart';
import '../ui/components/screen_title.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';
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

  /// What a KSh 100 line will look like, so the rate is not an abstraction.
  ///
  /// Static, because the panel that renders it is pure and takes its catalogue
  /// as an argument. Formatted through the same `formatMoney` the rest of the
  /// app uses, and the sentence comes from the ARB with the two figures as
  /// placeholders — the old version spliced raw ASCII digits into a literal,
  /// which is simultaneously un-localizable and wrong in any locale that groups
  /// decimals differently.
  static String workedExample(AppLocalizations l10n, int rate,
      {bool pricesIncludeVat = true}) {
    final Money gross = Money.fromMajor(100);
    final Money vat = vatComponentOf(gross,
        ratePercent: rate, pricesIncludeVat: pricesIncludeVat);
    // gen-l10n orders the generated parameters ALPHABETICALLY by placeholder
    // name, so `net` comes first and `vat` second regardless of the order they
    // appear in the ARB template. Passing them in the template's order prints
    // the VAT figure where the net figure belongs.
    return l10n.taxSettingsWorkedExample(
      formatMoney(gross - vat),
      formatMoney(vat),
    );
  }
}

class _TaxSettingsScreenState extends State<TaxSettingsScreen> {
  /// The rate as it will be saved: what the database holds.
  int _vatRatePercent = kDefaultVatRatePercent;

  /// The rate the slider is showing while it is dragged.
  ///
  /// Held apart from [_vatRatePercent] so a drag can preview the effect on the
  /// worked example without persisting anything, and so releasing the slider is
  /// the single commit that writes the setting and one audit row.
  int? _previewVatRate;

  /// The rate on screen: the preview while dragging, otherwise the saved one.
  int get _showingVatRate => _previewVatRate ?? _vatRatePercent;

  bool _pricesIncludeVat = true;
  bool _etimsEnabled = false;
  String _tillCode = '';
  String _tin = '';
  String _etimsDeviceId = '';
  TaxEntitySnapshot? _taxEntity;
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
    // This release deliberately cannot activate KRA/eTIMS. Clear any stale
    // local flag from an upgraded build instead of displaying a switch that
    // suggests the shop is filing when only local VAT reporting is active.
    final etimsOn = EtimsService.taxReportingActivated &&
        (prefs.getBool(EtimsService.etimsEnabledPrefKey) ?? false);
    if (!EtimsService.taxReportingActivated &&
        prefs.getBool(EtimsService.etimsEnabledPrefKey) == true) {
      await prefs.setBool(EtimsService.etimsEnabledPrefKey, false);
    }
    final backendLinked = await BackendService.isBackendLinked;
    final taxEntity =
        backendLinked ? await BackendService.fetchTaxEntity() : null;
    final managedVatRate = taxEntity?.managedVatRatePercent;
    if (managedVatRate != null) await db.setVatRatePercent(managedVatRate);
    if (!mounted) return;
    setState(() {
      _etimsEnabled = etimsOn;
      _vatRatePercent = managedVatRate ?? vatRate;
      _tillCode = tillCode;
      _tin = tin;
      _etimsDeviceId = device;
      _pricesIncludeVat = includesVat;
      _taxEntity = taxEntity;
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
    if (value && !(await BackendService.isBackendLinked)) {
      setState(() {
        _message = AppLocalizations.of(context).taxSettingsEtimsNotLinked;
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
    // Read before any await: the audit row below is attributed from the
    // session, and a BuildContext must not be held across one.
    final AppState state = context.read<AppState>();
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
      // The tax settings decide what every future receipt says, so a rate
      // changed at 11pm is the row an audit log exists to hold.
      await recordActionAudit(
        state,
        action: AuditAction.taxSettingsChanged,
        entity: AuditEntity.settings,
        entityId: 'tax',
        detail: _describeTaxChange(
          vatRatePercent: vatRatePercent,
          tillCode: tillCode,
          tin: tin,
          pricesIncludeVat: pricesIncludeVat,
        ),
      );
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
        _message = AppLocalizations.of(context).taxSettingsSaveFailed;
        _messageIsError = true;
      });
    } finally {
      // The drag is over either way: the slider stops previewing and shows the
      // saved rate, which keeps a failed save visibly unsuccessful.
      if (mounted) {
        setState(() {
          _previewVatRate = null;
          _saving = false;
        });
      }
    }
  }

  /// The change, in words, for the audit row.
  ///
  /// One sentence naming only the fields that moved: a row saying "tax changed"
  /// when only the till code moved is a row nobody can act on.
  String _describeTaxChange({
    int? vatRatePercent,
    String? tillCode,
    String? tin,
    bool? pricesIncludeVat,
  }) {
    final parts = <String>[
      if (vatRatePercent != null) 'VAT $vatRatePercent%',
      if (tillCode != null) 'till $tillCode',
      if (tin != null && tin.isNotEmpty) 'TIN $tin',
      if (pricesIncludeVat != null)
        pricesIncludeVat ? 'prices include VAT' : 'prices exclude VAT',
    ];
    return parts.isEmpty ? 'no change' : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    // The stateful screen owns the async work; it delegates to a widget that
    // takes the loaded values, so the presentation can be rendered from a
    // constructed value in a test without seeding four settings first.
    return TaxSettingsPanel(
      loading: _loading,
      saving: _saving,
      isAdmin: context.watch<AppState>().isAdmin,
      vatRatePercent: _showingVatRate,
      pricesIncludeVat: _pricesIncludeVat,
      onSaveVatRate: (int rate) => _save(vatRatePercent: rate),
      // Preview only: the panel's own copy of the rate moves with the drag and
      // is overwritten by the committed value once the save lands. Nothing is
      // written to the database or the audit log here.
      onPreviewVatRate: (int rate) =>
          mounted ? setState(() => _previewVatRate = rate) : null,
      onSetPricesIncludeVat: (bool v) => _save(pricesIncludeVat: v),
      tillCode: _tillCode,
      onEditTillCode: _saving ? null : _editTillCode,
      etimsEnabled: _etimsEnabled,
      taxReportingActivated: false,
      onToggleEtims: _saving ? null : _toggleEtims,
      tin: _tin,
      onEditTin: _saving ? null : _editTin,
      etimsDeviceId: _etimsDeviceId,
      onRefreshQueue: _saving ? null : _refreshQueue,
      message: _message,
      messageIsError: _messageIsError,
      taxEntity: _taxEntity,
      onEditTaxEntity: _saving ? null : _editTaxEntity,
      vatRateManagedByRule: _taxEntity?.managedVatRatePercent != null,
    );
  }

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
                AppLocalizations.of(context).taxSettingsTillCodeDialogHelp,
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
                    style: TextStyle(color: AppColors.of(context).danger)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(AppLocalizations.of(context).actionCancel)),
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
                  AppLocalizations.of(context).taxSettingsKraPinDialogHelp,
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
                        style: TextStyle(color: AppColors.of(context).danger)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(AppLocalizations.of(context).actionCancel)),
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
                      final kraPin = RegExp(r'^[AP]\d{9}[A-Z]$');
                      if (!kraPin.hasMatch(value)) {
                        setDialogState(() => error =
                            AppLocalizations.of(context).taxSettingsTinInvalid);
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
                        if (await BackendService.isBackendLinked) {
                          await BackendService.saveTaxEntity(
                            legalForm: _taxEntity?.legalForm ?? 'other',
                            displayLabel:
                                _taxEntity?.displayLabel ?? 'Taxpayer',
                            obligations: _taxEntity?.obligations ?? const [],
                            accountingPeriodStartMonth:
                                _taxEntity?.accountingPeriodStartMonth ?? 1,
                            status: _taxEntity?.status ?? 'needs_review',
                            effectiveFrom: DateTime.now().toUtc(),
                            outletReference: _taxEntity?.outletReference,
                            kraPin: value,
                          );
                        }
                        await DatabaseHelper.instance
                            .setSetting(DatabaseHelper.settingTin, value);
                        await DatabaseHelper.instance.setSetting(
                            DatabaseHelper.settingEtimsDeviceId, deviceId);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, value);
                        }
                      } catch (e) {
                        setDialogState(() {
                          submitting = false;
                          // Not linked is a configuration problem, not a KRA outage: say so plainly.
                          final l10n = AppLocalizations.of(context);
                          if (e is EtimsNotLinkedException ||
                              (e is StateError &&
                                  e.message
                                      .contains('not linked to backend'))) {
                            error = l10n.taxSettingsEtimsNotLinked;
                          } else {
                            error = l10n.taxSettingsKraUnreachable;
                          }
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

  Future<void> _editTaxEntity() async {
    final labelController = TextEditingController(
      text: _taxEntity?.displayLabel.isNotEmpty == true
          ? _taxEntity!.displayLabel
          : 'Taxpayer',
    );
    var legalForm = _taxEntity?.legalForm ?? 'other';
    final obligations = <String>{...?_taxEntity?.obligations};
    var etimsOnboardingStatus =
        _taxEntity?.etimsOnboardingStatus ?? 'not_started';
    var etimsMethod = _taxEntity?.etimsMethod;
    var submitting = false;
    String? error;
    final result = await showDialog<TaxEntitySnapshot>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Tax entity and outlet mapping'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                autofocus: true,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Display label'),
              ),
              DropdownButtonFormField<String>(
                initialValue: legalForm,
                decoration: const InputDecoration(labelText: 'Legal form'),
                items: const [
                  DropdownMenuItem(
                      value: 'individual', child: Text('Individual')),
                  DropdownMenuItem(
                      value: 'sole_proprietor', child: Text('Sole proprietor')),
                  DropdownMenuItem(
                      value: 'partnership', child: Text('Partnership')),
                  DropdownMenuItem(value: 'company', child: Text('Company')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: submitting
                    ? null
                    : (value) =>
                        setDialogState(() => legalForm = value ?? 'other'),
              ),
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Registered obligations'),
                ),
              ),
              for (final obligation in const [
                'vat',
                'etims',
                'tot',
                'income_tax',
                'withholding',
                'withholding_vat',
                'excise',
                'payroll',
              ])
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(obligation.toUpperCase()),
                  value: obligations.contains(obligation),
                  onChanged: submitting
                      ? null
                      : (value) => setDialogState(() {
                            if (value == true) {
                              obligations.add(obligation);
                            } else {
                              obligations.remove(obligation);
                            }
                          }),
                ),
              if (obligations.contains('etims')) ...[
                DropdownButtonFormField<String>(
                  initialValue: etimsOnboardingStatus,
                  decoration:
                      const InputDecoration(labelText: 'eTIMS onboarding'),
                  items: const [
                    DropdownMenuItem(
                        value: 'not_started', child: Text('Not started')),
                    DropdownMenuItem(
                        value: 'in_progress', child: Text('In progress')),
                    DropdownMenuItem(
                        value: 'onboarded', child: Text('Onboarded')),
                    DropdownMenuItem(
                        value: 'needs_review', child: Text('Needs review')),
                  ],
                  onChanged: submitting
                      ? null
                      : (value) => setDialogState(() {
                            etimsOnboardingStatus = value ?? 'not_started';
                          }),
                ),
                DropdownButtonFormField<String>(
                  initialValue: etimsMethod,
                  decoration: const InputDecoration(labelText: 'eTIMS method'),
                  items: const [
                    DropdownMenuItem(
                        value: 'online', child: Text('Online / eClient')),
                    DropdownMenuItem(value: 'oscu', child: Text('OSCU')),
                    DropdownMenuItem(value: 'vscu', child: Text('VSCU')),
                    DropdownMenuItem(value: 'epos', child: Text('ePOS')),
                    DropdownMenuItem(
                        value: 'non_vat_lite', child: Text('Non-VAT Lite')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: submitting
                      ? null
                      : (value) => setDialogState(() => etimsMethod = value),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: TextStyle(color: AppColors.of(context).danger)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.of(context).actionCancel),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final label = labelController.text.trim();
                      if (label.isEmpty) {
                        setDialogState(
                            () => error = 'A display label is required');
                        return;
                      }
                      setDialogState(() {
                        submitting = true;
                        error = null;
                      });
                      try {
                        final saved = await BackendService.saveTaxEntity(
                          legalForm: legalForm,
                          displayLabel: label,
                          obligations: obligations.toList()..sort(),
                          accountingPeriodStartMonth:
                              _taxEntity?.accountingPeriodStartMonth ?? 1,
                          status: _taxEntity?.status ?? 'needs_review',
                          effectiveFrom: DateTime.now().toUtc(),
                          etimsOnboardingStatus: etimsOnboardingStatus,
                          etimsMethod: etimsMethod,
                          outletReference: _taxEntity?.outletReference,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, saved);
                        }
                      } catch (_) {
                        setDialogState(() {
                          submitting = false;
                          error = 'Could not save the tax-entity mapping';
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save mapping'),
            ),
          ],
        ),
      ),
    );
    labelController.dispose();
    if (result == null || !mounted) return;
    setState(() {
      _taxEntity = result;
      _message = 'Tax-entity mapping saved';
      _messageIsError = false;
    });
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

  /// An identifier that is unique to this installation.
  ///
  /// Derived from the workspace it collides across restores and second phones,
  /// which makes two tills share one device id and collide on receipt numbers.
  /// Generated once and kept in preferences so it survives restarts but not a
  /// restore to a different handset — exactly the install-unique identity KRA
  /// needs to keep receipt numbers distinct.
  static const _etimsInstallDeviceIdKey = 'etims_install_device_id';

  Future<String> _deviceIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_etimsInstallDeviceIdKey);
    if (stored != null && stored.isNotEmpty) return stored;
    final fresh = List.generate(16, (_) => Random.secure().nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    await prefs.setString(_etimsInstallDeviceIdKey, fresh);
    return fresh;
  }
}

// ---------------------------------------------------------------------------
// Sections
//
// Tax is the last screen on the old Material layout, so it takes the same
// treatment Settings took: a header, a card, and rows of the shared shape.
// ---------------------------------------------------------------------------

/// The whole screen as one constructed value.
///
/// Split from [TaxSettingsScreen] for the same reason [SettingsPanel] exists:
/// the presentation renders from a value, so a test can assert the layout
/// without seeding four persisted settings into a database first.
class TaxSettingsPanel extends StatelessWidget {
  const TaxSettingsPanel({
    super.key,
    required this.loading,
    required this.saving,
    required this.isAdmin,
    required this.vatRatePercent,
    required this.pricesIncludeVat,
    required this.onSaveVatRate,
    required this.onPreviewVatRate,
    required this.onSetPricesIncludeVat,
    required this.tillCode,
    required this.onEditTillCode,
    required this.etimsEnabled,
    this.taxReportingActivated = false,
    required this.onToggleEtims,
    required this.tin,
    required this.onEditTin,
    required this.etimsDeviceId,
    required this.onRefreshQueue,
    required this.message,
    required this.messageIsError,
    this.taxEntity,
    this.onEditTaxEntity,
    this.vatRateManagedByRule = false,
  });

  final bool loading;
  final bool saving;
  final bool isAdmin;

  final int vatRatePercent;
  final bool pricesIncludeVat;
  final ValueChanged<int> onSaveVatRate;

  /// Updates the slider's position while it is being dragged, WITHOUT writing.
  ///
  /// Separate from [onSaveVatRate] so the preview is local state: the preview
  /// updates the worked example as the owner drags, but nothing is persisted —
  /// and no audit row is written — until the value is released.
  final ValueChanged<int> onPreviewVatRate;
  final ValueChanged<bool> onSetPricesIncludeVat;

  final String tillCode;

  /// Null while a save is in flight: the row stays, dimmed, so the layout does
  /// not jump between idle and busy.
  final VoidCallback? onEditTillCode;

  final bool etimsEnabled;
  final bool taxReportingActivated;
  final ValueChanged<bool>? onToggleEtims;
  final String tin;
  final VoidCallback? onEditTin;
  final String etimsDeviceId;
  final VoidCallback? onRefreshQueue;

  final String? message;
  final bool messageIsError;
  final TaxEntitySnapshot? taxEntity;
  final VoidCallback? onEditTaxEntity;
  final bool vatRateManagedByRule;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    // The screen names itself on the canvas. It used to open straight into a
    // VAT slider with no title anywhere on it, which is the one place in the
    // app where the figures on screen belong to a legal document and the
    // reader needs to know which document they are configuring.
    final Widget title = ScreenTitle(
      title: l10n.taxSettingsTitle,
      // The page already insets its content by `md`; the title's own default
      // inset would push it off the gutter the cards sit on.
      padding: EdgeInsetsDirectional.only(bottom: spacing.md),
    );

    // Defence in depth. Settings does not show the tab to a non-admin, but a
    // screen that mints a TIN should not depend on that alone.
    if (!isAdmin) {
      return AdaptivePage(
        scrollable: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            title,
            const AdminOnlyNotice(),
          ],
        ),
      );
    }

    if (loading) {
      return AdaptivePage(
        scrollable: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            title,
            const TaxSkeleton(),
          ],
        ),
      );
    }

    return AdaptivePage(
      scrollable: true,
      maxContentWidth: 880,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          title,
          TaxSection(
            label: 'Tax entity and outlets',
            children: <Widget>[
              SettingsInfoRow(
                icon: Icons.account_balance_outlined,
                title: taxEntity == null
                    ? 'Tax entity is not configured'
                    : taxEntity!.displayLabel,
                subtitle: taxEntity == null
                    ? 'Link this shop to a taxpayer before configuring tax rules.'
                    : '${taxEntity!.legalForm} · ${taxEntity!.status} · '
                        '${taxEntity!.linkedShopCount} linked shop(s) · '
                        'turnover ${formatMoney(taxEntity!.turnover)}',
              ),
              SettingsNavRow(
                icon: Icons.edit_outlined,
                title: 'Configure tax entity',
                subtitle: 'Set the taxpayer identity used for this outlet.',
                trailing: 'Configure',
                onTap: onEditTaxEntity,
              ),
              if (taxEntity != null && taxEntity!.obligations.isNotEmpty)
                SettingsInfoRow(
                  icon: Icons.assignment_turned_in_outlined,
                  title: 'Registered obligations',
                  subtitle: taxEntity!.obligations.join(', '),
                ),
              ...?taxEntity?.conditionalObligations.map(
                (obligation) => SettingsInfoRow(
                  icon: obligation.status ==
                          'not_supported_for_automated_calculation'
                      ? Icons.info_outline
                      : Icons.rule_outlined,
                  title: '${obligation.taxType.toUpperCase()} obligation',
                  subtitle: obligation.status ==
                          'not_supported_for_automated_calculation'
                      ? 'Registered but not supported for automated calculation.'
                      : '${obligation.status} · ${obligation.reviewedRuleCount} reviewed rule(s)',
                ),
              ),
              if (taxEntity != null && taxEntity!.obligations.contains('etims'))
                SettingsInfoRow(
                  icon: Icons.receipt_long_outlined,
                  title: 'eTIMS onboarding',
                  subtitle:
                      '${taxEntity!.etimsOnboardingStatus}${taxEntity!.etimsMethod == null ? '' : ' · ${taxEntity!.etimsMethod}'}',
                ),
              if (taxEntity != null && taxEntity!.obligations.contains('tot'))
                SettingsInfoRow(
                  icon: Icons.calculate_outlined,
                  title: 'TOT estimate (not filed)',
                  subtitle: taxEntity!.totEstimate == null
                      ? 'Needs an approved effective TOT rule.'
                      : '${formatMoney(taxEntity!.totEstimate!)} · ${taxEntity!.totStatus ?? 'needs review'}${taxEntity!.totDueDate == null ? '' : ' · due ${taxEntity!.totDueDate!.toLocal().toIso8601String().split('T').first}'}',
                ),
              if (taxEntity?.totReturn != null)
                SettingsInfoRow(
                  icon: Icons.assignment_turned_in_outlined,
                  title: 'TOT period evidence',
                  subtitle:
                      '${formatMoney(taxEntity!.totReturn!.estimate)} on ${formatMoney(taxEntity!.totReturn!.grossSales)} gross sales · ${taxEntity!.totReturn!.status} (not a filing)',
                ),
              if (taxEntity?.vatReport != null)
                SettingsInfoRow(
                  icon: Icons.fact_check_outlined,
                  title: 'VAT period reconciliation',
                  subtitle:
                      '${formatMoney(taxEntity!.vatReport!.adjustedOutputVat)} adjusted output · ${formatMoney(taxEntity!.vatReport!.creditNoteVat)} credit-note VAT · ${taxEntity!.vatReport!.status}${taxEntity!.vatReport!.linesWithoutRuleSnapshot == 0 ? '' : ' · ${taxEntity!.vatReport!.linesWithoutRuleSnapshot} lines need review'}',
                ),
              if (taxEntity?.inputVatReport != null)
                SettingsInfoRow(
                  icon: Icons.receipt_long_outlined,
                  title: 'Input VAT evidence',
                  subtitle:
                      '${formatMoney(taxEntity!.inputVatReport!.eligibleInputVat)} eligible · ${taxEntity!.inputVatReport!.unmatchedCount} unmatched · ${taxEntity!.inputVatReport!.status}',
                ),
              if (taxEntity?.vatReturn != null)
                SettingsInfoRow(
                  icon: Icons.assignment_outlined,
                  title: 'VAT return evidence',
                  subtitle:
                      '${formatMoney(taxEntity!.vatReturn!.netPayable)} net · ${taxEntity!.vatReturn!.status} (not a filing)',
                ),
              if (taxEntity?.etimsQueue != null)
                SettingsInfoRow(
                  icon: Icons.cloud_upload_outlined,
                  title: 'eTIMS invoice queue',
                  subtitle:
                      '${taxEntity!.etimsQueue!.issued} issued · ${taxEntity!.etimsQueue!.pending} pending · ${taxEntity!.etimsQueue!.rejected} rejected · ${taxEntity!.etimsQueue!.status}',
                ),
              if (taxEntity != null && taxEntity!.kraPinSet)
                SettingsInfoRow(
                  icon: Icons.verified_outlined,
                  title: 'KRA PIN protected',
                  subtitle: 'PIN ending ${taxEntity!.kraPinLast4 ?? '****'}',
                ),
              if (taxEntity != null && taxEntity!.rules.isEmpty)
                const SettingsInfoRow(
                  icon: Icons.rule_folder_outlined,
                  title: 'No approved tax rules',
                  subtitle: 'Tax rules need review before they can be applied.',
                ),
              ...?taxEntity?.rules.map(
                (rule) => SettingsInfoRow(
                  icon: Icons.rule_outlined,
                  title: '${rule.taxType.toUpperCase()} · ${rule.scope}',
                  subtitle:
                      '${rule.status} · source: ${rule.sourceReference ?? rule.sourceUrl}',
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.of(context).md),
          // VAT: the rate, what it does to a real price, and whether shelf
          // prices already contain it.
          TaxSection(
            label: l10n.taxSettingsVatSection,
            children: <Widget>[
              SettingsInfoRow(
                icon: Icons.percent,
                title: l10n.taxSettingsVatRateLine(vatRatePercent),
                subtitle: vatRatePercent == 0
                    ? l10n.taxSettingsVatExempt
                    : TaxSettingsScreen.workedExample(l10n, vatRatePercent,
                        pricesIncludeVat: pricesIncludeVat),
              ),
              if (vatRateManagedByRule)
                const SettingsInfoRow(
                  icon: Icons.verified_outlined,
                  title: 'VAT rate is rule-managed',
                  subtitle: 'The approved taxpayer rule controls new sales.',
                ),
              // The rate is a slider plus Apply rather than a text field: a
              // shop picking between 0% and 25% is choosing, not typing, and a
              // keyboard invites a 16.5% a receipt must never carry.
              Row(
                children: <Widget>[
                  Expanded(
                    child: Slider(
                      value: vatRatePercent.toDouble(),
                      // 0 to 25 in whole steps. Kenya's standard is 16; 0
                      // means exempt. Anything above 25 is not a rate any real
                      // Kenyan shop faces and would only produce absurd VAT
                      // figures.
                      min: 0,
                      max: 25,
                      divisions: 25,
                      label: l10n.taxVatRatePercent(vatRatePercent),
                      // Announced, because a slider's value is invisible to a
                      // screen reader otherwise — and announced through the
                      // catalogue, so the words are the app's words.
                      // The rate is NOT persisted as the slider moves: the value
                      // stays local to the panel and is committed on release, so
                      // one drag writes ONE `tax_settings_changed` row instead of
                      // one per division tick. Every tick used to reach `_save`,
                      // which wrote the setting and an audit row each time.
                      semanticFormatterCallback: (double v) =>
                          l10n.taxSettingsVatRateSpoken(v.round()),
                      onChanged: saving || vatRateManagedByRule
                          ? null
                          : (double v) => onPreviewVatRate(v.round()),
                      onChangeEnd: saving || vatRateManagedByRule
                          ? null
                          : (double v) => onSaveVatRate(v.round()),
                    ),
                  ),
                  SizedBox(width: AppSpacing.of(context).sm),
                  FilledButton(
                    onPressed: saving || vatRateManagedByRule
                        ? null
                        : () => onSaveVatRate(vatRatePercent),
                    child: Text(l10n.taxSettingsApplyAction),
                  ),
                ],
              ),
              SettingsSwitchRow(
                icon: Icons.sell_outlined,
                title: l10n.taxSettingsPricesIncludeVat,
                subtitle: l10n.taxSettingsPricesIncludeVatSubtitle,
                value: pricesIncludeVat,
                enabled: !saving,
                onChanged: onSetPricesIncludeVat,
              ),
            ],
          ),
          SizedBox(height: AppSpacing.of(context).md),
          // Receipt numbering: the till code KRA matches against.
          TaxSection(
            label: l10n.taxSettingsReceiptNumberingSection,
            children: <Widget>[
              SettingsNavRow(
                icon: Icons.tag_outlined,
                title: l10n.taxSettingsTillCode,
                subtitle: l10n.taxSettingsTillCodeHelp(tillCode),
                trailing: l10n.taxSettingsChangeAction,
                onTap: onEditTillCode,
              ),
            ],
          ),
          SizedBox(height: AppSpacing.of(context).md),
          // KRA eTIMS: issuance, the PIN it is filed against, and the queue.
          TaxSection(
            label: l10n.taxSettingsEtimsSection,
            children: <Widget>[
              if (!taxReportingActivated)
                SettingsInfoRow(
                  icon: Icons.lock_outline,
                  title: l10n.taxSettingsNotActivatedStatus,
                  subtitle: l10n.taxSettingsNotActivatedSubtitle,
                ),
              if (!taxReportingActivated) const Divider(height: 1),
              SettingsSwitchRow(
                icon: Icons.receipt_long_outlined,
                title: l10n.taxSettingsIssueEtimsTitle,
                subtitle: etimsEnabled
                    ? l10n.taxSettingsEtimsOnSubtitle
                    : l10n.taxSettingsEtimsOffSubtitle,
                value: etimsEnabled,
                enabled: !saving && taxReportingActivated,
                onChanged: onToggleEtims ?? (bool _) {},
              ),
              if (etimsEnabled) const Divider(height: 1),
              SettingsNavRow(
                icon: Icons.badge_outlined,
                title: tin.isEmpty
                    ? l10n.taxSettingsTinNotRegistered
                    : l10n.taxTaxpayerPIN(tin),
                subtitle: tin.isEmpty
                    ? l10n.taxSettingsTinNotRegisteredHelp
                    : l10n.taxSettingsTinRegisteredHelp,
                trailing: tin.isEmpty
                    ? l10n.taxSettingsRegisterAction
                    : l10n.taxSettingsChangeAction,
                onTap: onEditTin,
              ),
              if (etimsDeviceId.isNotEmpty)
                SettingsInfoRow(
                  icon: Icons.devices_outlined,
                  title: l10n.taxSettingsRegisteredDevice,
                  subtitle: etimsDeviceId,
                ),
              SettingsNavRow(
                icon: Icons.cloud_upload_outlined,
                title: l10n.taxSettingsWaitForReceipts,
                subtitle: l10n.taxSettingsWaitForReceiptsSubtitle,
                onTap: onRefreshQueue,
              ),
            ],
          ),
          // The result of the last action, announced rather than only shown:
          // "Saved" is information, and information only the eye can reach is
          // information a screen reader never gets.
          if (message != null) ...<Widget>[
            SizedBox(height: AppSpacing.of(context).md),
            Semantics(
              liveRegion: true,
              child: Text(
                message!,
                style: AppTypography.of(context).bodyMedium?.copyWith(
                      color: messageIsError
                          ? AppColors.of(context).danger
                          : AppColors.of(context).success,
                    ),
              ),
            ),
          ],
          SizedBox(height: AppSpacing.of(context).lg),
          Center(
            child: PoweredByNerva(
              style: AppTypography.of(context).bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sections
//
// Tax is the last screen on the old Material layout, so it takes the same
// treatment Settings took: a header, a card, and rows of the shared shape. The
// section wrapper is local rather than shared because the two screens word
// their help lines differently and a card that carries rows of two different
// kinds is easier to read as two widgets than as one with three flags.
// ---------------------------------------------------------------------------

/// One tax section: a header and a card of rows.
class TaxSection extends StatelessWidget {
  const TaxSection({super.key, required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(padding: EdgeInsets.zero, label: label),
        SizedBox(height: spacing.sm),
        SurfaceCard(
          // The transparent Material is what lets the rows inside draw ink:
          // `SurfaceCard` paints a decoration, not a Material, and an `InkWell`
          // without one throws at build time.
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown to a non-admin who reached this route directly.
///
/// A screen that mints a TIN should not depend on Settings hiding the tab, and a
/// dead screen with no explanation is worse than this one with a sentence.
class AdminOnlyNotice extends StatelessWidget {
  const AdminOnlyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(
            Icons.lock_outline,
            size: 32,
            color: colors.onSurfaceMuted,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.taxSettingsAdminOnly,
          textAlign: TextAlign.center,
          style: AppTypography.of(context).bodyMedium,
        ),
      ],
    );
  }
}

/// The first load, drawn as the rows it is about to become.
///
/// A skeleton rather than a spinner because the shape says what is coming, and
/// nothing moves when it arrives. The load reads four settings, so it is fast —
/// but a shop on a slow phone with a large database still gets a frame of it,
/// and a flash of empty cards reads as "tax is not configured".
class TaxSkeleton extends StatelessWidget {
  const TaxSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppShapes shapes = AppShapes.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List<Widget>.generate(3, (int section) {
        return Padding(
          padding: EdgeInsets.only(bottom: spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The header's slot, narrower than the card's rows.
              FractionallySizedBox(
                widthFactor: 0.35,
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: shapes.barRadius,
                  ),
                ),
              ),
              SizedBox(height: spacing.sm),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List<Widget>.generate(2, (int row) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: spacing.sm),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: colors.surfaceSunken,
                              borderRadius: shapes.barRadius,
                            ),
                          ),
                          SizedBox(width: spacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                FractionallySizedBox(
                                  widthFactor: row.isEven ? 0.6 : 0.45,
                                  child: Container(
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: colors.surfaceSunken,
                                      borderRadius: shapes.barRadius,
                                    ),
                                  ),
                                ),
                                SizedBox(height: spacing.xs),
                                FractionallySizedBox(
                                  widthFactor: 0.75,
                                  child: Container(
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: colors.surfaceSunken,
                                      borderRadius: shapes.barRadius,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
