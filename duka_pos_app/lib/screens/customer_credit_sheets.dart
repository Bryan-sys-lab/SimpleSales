// The customer's own account: detail, a payment received, a reminder, a
// statement, and the editor — the sheets of feature 7 (customers and credit).
//
// ## THE ORDER OF WRITING
//
// Every act here is a LEDGER write through DatabaseHelper; the screen's own
// opinion of the balance is always read back AFTER the write, from the cache
// the transaction just updated. A sheet that computes the "new balance"
// locally and shows it before the database agrees would be showing a number
// the shop cannot yet bank on.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/audit_log.dart';
import '../models/credit.dart';
import 'package:provider/provider.dart';

import '../services/audit_actor.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/states.dart';
import '../ui/components/status.dart';
import '../utils/kenya_phone.dart';
import '../utils/money.dart';

/// The customer's detail, as a sheet.
///
/// Returns true when anything about the customer changed (a payment, an
/// edit, a deactivation), so the caller reloads its list.
Future<bool> showCustomerDetailSheet(BuildContext context, Customer customer,
    {bool editable = true}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _CustomerDetailSheet(customer: customer, editable: editable),
  );
  return result ?? false;
}

class _CustomerDetailSheet extends StatefulWidget {
  const _CustomerDetailSheet({required this.customer, required this.editable});

  final Customer customer;
  final bool editable;

  @override
  State<_CustomerDetailSheet> createState() => _CustomerDetailSheetState();
}

class _CustomerDetailSheetState extends State<_CustomerDetailSheet> {
  late Customer _customer = widget.customer;

  /// The customer's row id, or null for an unsaved customer.
  int? get _customerId => widget.customer.id;
  List<CreditLedgerEntry> _entries = const [];
  int _shopDefaultLimit = 0;
  bool _loading = true;
  String? _error;

  /// Whether anything changed while the sheet was open — returned to the
  /// caller, who reloads its list. A payment or an edit sets it; a peek
  /// does not.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = DatabaseHelper.instance;
      // Sequential reads — small tables, one customer; a fanned-out map of
      // index slices buys nothing and names nothing.
      final List<CreditLedgerEntry> entries = _customerId == null
          ? const <CreditLedgerEntry>[]
          : await db.getCreditEntries(_customerId!);
      final int defaultLimit = await db.getCreditDefaultLimit();
      final Customer? fresh =
          _customerId == null ? null : await db.getCustomerById(_customerId!);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _shopDefaultLimit = defaultLimit;
        if (fresh != null) _customer = fresh;
        _loading = false;
        _error = null;
      });
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message.toString();
      });
    }
  }

  Future<void> _addPayment() async {
    final bool taken = await showCreditPaymentSheet(context, _customer);
    if (!taken) return;
    _changed = true;
    await _load();
    if (!mounted) return;
    setState(() {}); // the balance header refreshes from _customer.
  }

  Future<void> _edit() async {
    final Customer? updated = await showCustomerEditSheet(context, _customer);
    if (updated == null) return;
    _changed = true;
    await _load();
  }

  /// The reminder: the SHop's template + the balance, to the shop's own
  /// composer. The app opens the compose screen; it never sends by itself,
  /// and the customer's number is handed over ONLY to the messaging app.
  Future<void> _sendReminder() async {
    if (_customer.phone == null || !mounted) return;
    final db = DatabaseHelper.instance;
    final template = await db.getCreditReminderTemplate();
    final shopName = await db.getShopName();
    // The message is built from the SHOP'S OWN template — the shop wording,
    // the customer's first name, and the balance. The app opens the composer;
    // it never sends by itself (spec 7.4).
    final message = buildReminderMessage(
      template: template,
      shopName: shopName,
      customerName: _customer.name,
      balance: Money.fromMinor(_customer.balanceMinor),
    );
    final target = phoneComposeTarget(_customer.phone, whatsapp: true);
    if (target == null || !mounted) return;
    final url =
        Uri.parse('https://wa.me/$target?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context).customerReminderFailed)),
      );
    }
  }

  Future<void> _shareStatement() async {
    if (!mounted) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final buffer = StringBuffer();
    buffer.writeln(l10n.customerStatementTitle(_customer.name));
    for (final entry in _entries.take(30)) {
      buffer.writeln(
        '${entry.createdAt}\t${statementLineLabel(l10n, entry)}\t'
        '${formatMoney(Money.fromMinor(entry.amountMinor))}',
      );
    }
    final balance = formatMoney(Money.fromMinor(_customer.balanceMinor));
    buffer.writeln(l10n.customerStatementBalance(balance));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.customerStatementTitle(_customer.name)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SelectableText(buffer.toString()),
              const SizedBox(height: 12),
              // THE SHARE: the WhatsApp compose with the shop's template.
              Text(l10n.customerStatementShareHint),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: buffer.toString()));
              Navigator.pop(dialogContext);
            },
            child: Text(l10n.customerCopyStatement),
          ),
        ],
      ),
    );
  }

  Future<void> _deactivate() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    // Read BEFORE the await: every fact the call needs is in hand by the time
    // the sheet is gone.
    final state = context.read<AppState>();
    try {
      await DatabaseHelper.instance.deactivateCustomer(_customer.id!);
      await recordActionAudit(
        state,
        action: AuditAction.creditAdjusted,
        entity: AuditEntity.customer,
        entityId: 'customer-${_customer.id}',
        detail: 'deactivated a customer',
      );
      if (!mounted) return;
      navigator.pop(true);
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(l10n.creditDeactivateFailed(error.message.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(spacing.lg, spacing.lg, spacing.lg,
              spacing.lg + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(_customer.name, style: type.titleLarge),
                  ),
                  if (widget.editable)
                    IconButton(
                      onPressed: _edit,
                      tooltip: l10n.customerEditAction,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  // Done: closes the sheet, and carries whether anything the
                  // caller shows changed.
                  TextButton(
                    onPressed: () => Navigator.pop(context, _changed),
                    child: Text(l10n.actionDone),
                  ),
                ],
              ),
              if (_customer.phoneDisplay != null)
                Text(
                  _customer.phoneDisplay!,
                  style:
                      type.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
                ),
              SizedBox(height: spacing.md),
              // THE BALANCE, large. In credit (a negative balance) is GOOD
              // news and says so.
              Text(
                formatMoney(Money.fromMinor(_customer.balanceMinor.abs())),
                style: type.headlineMedium,
              ),
              Text(
                _customer.balanceMinor > 0
                    ? l10n.customerBalanceOwedHeading
                    : _customer.balanceMinor < 0
                        ? l10n.customerBalanceCreditHeading
                        : l10n.customerBalanceClearHeading,
                style: type.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
              ),
              SizedBox(height: spacing.xs),
              // THE LIMIT + the headroom under it (spec 7.4).
              Builder(builder: (BuildContext context) {
                final int limit = _customer.effectiveLimit(_shopDefaultLimit);
                return Text(
                  l10n.customerBalanceLimitHeading(
                    formatMoney(Money.fromMinor(limit)),
                    formatMoney(Money.fromMinor(
                        (limit - _customer.balanceMinor).abs())),
                  ),
                  style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
                );
              }),
              if (widget.editable) ...<Widget>[
                SizedBox(height: spacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _addPayment,
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(l10n.customerAddPayment),
                      ),
                    ),
                    SizedBox(width: spacing.sm),
                    OutlinedButton.icon(
                      onPressed: _customer.phone == null ? null : _sendReminder,
                      icon: const Icon(Icons.sms_outlined),
                      label: Text(l10n.customerRemindAction),
                    ),
                  ],
                ),
                SizedBox(height: spacing.sm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _shareStatement,
                        icon: const Icon(Icons.description_outlined),
                        label: Text(l10n.customerStatementAction),
                      ),
                    ),
                    SizedBox(width: spacing.sm),
                    OutlinedButton.icon(
                      onPressed: _deactivate,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.danger,
                      ),
                      icon: const Icon(Icons.person_off_outlined),
                      label: Text(l10n.customerDeactivateAction),
                    ),
                  ],
                ),
              ],
              SizedBox(height: spacing.md),
              Text(l10n.creditHistoryLabel, style: type.labelLarge),
              if (_error != null) ...[
                SizedBox(height: spacing.sm),
                ErrorStateView(message: _error!, onRetry: _load),
              ] else if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_entries.isEmpty)
                Padding(
                  padding: EdgeInsets.all(spacing.md),
                  child: EmptyStateView(
                    title: l10n.creditHistoryEmptyTitle,
                    message: l10n.creditHistoryEmptyMessage,
                  ),
                )
              else
                ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: <Widget>[
                    for (final CreditLedgerEntry entry in _entries)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          entry.amountMinor >= 0
                              ? Icons.add_circle_outline
                              : Icons.remove_circle_outline,
                          color: entry.amountMinor >= 0
                              ? colors.danger
                              : colors.success,
                        ),
                        title: Text(statementLineLabel(l10n, entry),
                            style: type.bodyMedium),
                        subtitle: Text(
                          '${entry.createdAt} ${entry.reference ?? ''}'.trim(),
                          style: type.bodySmall
                              ?.copyWith(color: colors.onSurfaceMuted),
                        ),
                        trailing: Text(
                          formatMoney(Money.fromMinor(entry.amountMinor)),
                          style: type.bodyMedium,
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

/// The one-line label an entry carries on the history and the statement.
String statementLineLabel(AppLocalizations l10n, CreditLedgerEntry entry) {
  switch (entry.entryType) {
    case CreditEntryType.charge:
      return l10n.creditEntryCharge;
    case CreditEntryType.payment:
      return l10n.creditEntryPayment;
    case CreditEntryType.adjustment:
      return l10n.creditEntryAdjustment;
    case CreditEntryType.writeoff:
      return l10n.creditEntryWriteoff;
    case CreditEntryType.returnCredit:
      return l10n.creditEntryReturn;
  }
}

/// Adds or edits a customer.
///
/// Returns the SAVED customer (re-read from the database, so the caller's
/// next balance is the ledger's, not the form's), or null when dismissed.
/// With `null` as the customer it CREATES.
Future<Customer?> showCustomerEditSheet(
    BuildContext context, Customer? customer) async {
  final result = await showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CustomerEditSheet(customer: customer),
  );
  if (result == null || result.id == null) return null;
  return DatabaseHelper.instance.getCustomerById(result.id!);
}

class _CustomerEditSheet extends StatefulWidget {
  const _CustomerEditSheet({this.customer});

  final Customer? customer;

  @override
  State<_CustomerEditSheet> createState() => _CustomerEditSheetState();
}

class _CustomerEditSheetState extends State<_CustomerEditSheet> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _limit = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final Customer? customer = widget.customer;
    _name.text = customer?.name ?? '';
    // The phone shown is the DISPLAY form (07xx); stored, it is canonical —
    // the display form is what a person re-types.
    _phone.text = customer?.phoneDisplay ?? '';
    _notes.text = customer?.notes ?? '';
    _limit.text = customer?.creditLimitMinor == null
        ? ''
        : Money.fromMinor(customer!.creditLimitMinor!).asMajor.toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final String typed = _phone.text.trim();
      // Canonical (+254…) or nothing — the display form is for eyes, never
      // for storage: two spellings of one customer would be two customers.
      final String? phone = typed.isEmpty ? null : normaliseKenyanPhone(typed);
      final double? limitMajor = double.tryParse(_limit.text.trim());
      final Customer customer = Customer(
        id: widget.customer?.id,
        uuid: widget.customer?.uuid ?? '',
        name: _name.text.trim(),
        phone: phone,
        notes: _notes.text.trim(),
        creditLimitMinor:
            limitMajor == null ? null : Money.fromMajor(limitMajor).minorUnits,
        balanceMinor: widget.customer?.balanceMinor ?? 0,
        active: widget.customer?.active ?? true,
        createdAt:
            widget.customer?.createdAt ?? DateTime.now().toIso8601String(),
      );
      final int id = await DatabaseHelper.instance.upsertCustomer(
        Customer(
          id: customer.id,
          uuid: customer.uuid.isEmpty ? _newUuid() : customer.uuid,
          name: customer.name,
          phone: customer.phone,
          notes: customer.notes,
          creditLimitMinor: customer.creditLimitMinor,
          balanceMinor: widget.customer?.balanceMinor ?? 0,
          active: widget.customer?.active ?? true,
          createdAt: customer.createdAt,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.customerSavedTitle)),
      );
      Navigator.pop(
          context,
          Customer(
            id: id,
            uuid: customer.uuid,
            name: customer.name,
            phone: customer.phone,
            creditLimitMinor: customer.creditLimitMinor,
            balanceMinor: widget.customer?.balanceMinor ?? 0,
            active: widget.customer?.active ?? true,
            createdAt: customer.createdAt,
          ));
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message.toString();
      });
    }
  }

  String _newUuid() {
    final rng = DateTime.now().microsecondsSinceEpoch;
    final r = rng.remainder(0xffffff);
    final hex = r.abs().toRadixString(16).padLeft(6, '0');
    return 'c-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}$hex';
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(spacing.lg, spacing.lg, spacing.lg,
            spacing.lg + MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                widget.customer == null
                    ? l10n.customerAddAction
                    : l10n.customerEditAction,
                style: type.titleLarge,
              ),
              SizedBox(height: spacing.md),
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.name],
                decoration: InputDecoration(
                  labelText: l10n.customerNameLabel,
                ),
                validator: (String? value) => (value ?? '').trim().isEmpty
                    ? l10n.supplierNameTooShort
                    : null,
              ),
              SizedBox(height: spacing.sm),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const <String>[AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d +]')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.supplierPhoneLabel,
                  helperText: l10n.supplierPhoneHelper,
                ),
                validator: (String? value) {
                  final String typed = (value ?? '').trim();
                  if (typed.isEmpty) return null;
                  return normaliseKenyanPhone(typed) == null
                      ? l10n.supplierPhoneInvalid
                      : null;
                },
              ),
              SizedBox(height: spacing.sm),
              TextFormField(
                controller: _limit,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.customerLimitLabel,
                  helperText: l10n.customerLimitHelper,
                ),
                validator: (String? value) {
                  final String typed = value?.trim() ?? '';
                  if (typed.isEmpty) return null;
                  final double? parsed = double.tryParse(typed);
                  if (parsed == null || parsed < 0) {
                    return l10n.customerLimitInvalid;
                  }
                  return null;
                },
              ),
              SizedBox(height: spacing.sm),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (String _) => _save(),
                decoration: InputDecoration(
                  labelText: l10n.customerNotesLabel,
                ),
              ),
              if (_error != null) ...<Widget>[
                SizedBox(height: spacing.sm),
                PersistentBanner(
                  tone: StatusTone.danger,
                  icon: Icons.error_outline,
                  message: _error!,
                ),
              ],
              SizedBox(height: spacing.md),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.customerSaveAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A repayment, recorded against the ledger.
///
/// Returns true when it took. The amount starts at the WHOLE balance (the
/// usual case), the method at cash (the usual repayment), and the note is
/// optional; an M-Pesa code is asked for as the reference when the method is
/// mpesa. A cash repayment NEEDS the open shift — the drawer it adds to —
/// and the database says so when there is none (spec 7.4).
Future<bool> showCreditPaymentSheet(
    BuildContext context, Customer customer) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CreditPaymentSheet(customer: customer),
  );
  return result ?? false;
}

class _CreditPaymentSheet extends StatefulWidget {
  const _CreditPaymentSheet({required this.customer});

  final Customer customer;

  @override
  State<_CreditPaymentSheet> createState() => _CreditPaymentSheetState();
}

class _CreditPaymentSheetState extends State<_CreditPaymentSheet> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(
    text: Money.fromMinor(widget.customer.balanceMinor).asMajor.toString(),
  );
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _method = 'cash';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppState state = context.read<AppState>();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final double? major = double.tryParse(_amount.text.trim());
      if (major == null || major <= 0) {
        setState(() {
          _saving = false;
          _error = l10n.creditPaymentAmountInvalid;
        });
        return;
      }
      await DatabaseHelper.instance.recordCreditRepayment(
        customerId: widget.customer.id!,
        amount: Money.fromMajor(major),
        method: _method,
        reference:
            _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        staffId: state.currentStaffId,
        staffName: state.currentStaffName ?? '',
      );
      await recordActionAudit(
        state,
        action: AuditAction.creditRepayment,
        entity: AuditEntity.customer,
        entityId: 'customer-${widget.customer.id}',
        detail: 'repaid ${_amount.text} $_method ${_reference.text.trim()}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.creditPaymentTaken(
              widget.customer.name, _amount.text.trim())),
        ),
      );
      Navigator.pop(context, true);
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(spacing.lg, spacing.lg, spacing.lg,
            spacing.lg + MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(widget.customer.name, style: type.titleLarge),
              Text(
                l10n.creditPaymentOwes(
                    formatMoney(Money.fromMinor(widget.customer.balanceMinor))),
                style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
              ),
              SizedBox(height: spacing.md),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.creditPaymentAmountLabel,
                  prefixText: 'KSh ',
                  helperText: l10n.creditPaymentAmountHelper,
                ),
                validator: (String? value) {
                  final double? parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null || parsed <= 0) {
                    return l10n.creditPaymentAmountInvalid;
                  }
                  return null;
                },
              ),
              SizedBox(height: spacing.sm),
              SegmentedButton<String>(
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(
                    value: 'cash',
                    label: Text(l10n.creditPaymentCash),
                  ),
                  ButtonSegment<String>(
                    value: 'mpesa',
                    label: Text(l10n.creditPaymentMpesa),
                  ),
                ],
                selected: <String>{_method},
                onSelectionChanged: (Set<String> value) =>
                    setState(() => _method = value.first),
              ),
              if (_method == 'mpesa') ...<Widget>[
                SizedBox(height: spacing.sm),
                TextFormField(
                  controller: _reference,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (String value) => _save(),
                  decoration: InputDecoration(
                    labelText: l10n.creditPaymentCodeLabel,
                  ),
                ),
              ],
              SizedBox(height: spacing.sm),
              if (_error != null) ...<Widget>[
                PersistentBanner(
                  tone: StatusTone.danger,
                  icon: Icons.error_outline,
                  message: _error!,
                ),
                SizedBox(height: spacing.sm),
              ],
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.creditPaymentConfirmAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The customer picker for taking a sale on account.
///
/// Search, tap to choose; the "add one" row is the picker's own form section,
/// because the sale is mid-service and cannot be sent to another screen. A
/// customer's row carries the balance and the ROOM under the limit — the two
/// facts a decision to extend credit is made on.
Future<Customer?> showCustomerPickerSheet(BuildContext context) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) => const CustomerPickerSheet(),
  );
}

class CustomerPickerSheet extends StatefulWidget {
  const CustomerPickerSheet({super.key});

  @override
  State<CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<CustomerPickerSheet> {
  final TextEditingController _search = TextEditingController();
  List<Customer> _customers = const <Customer>[];
  int _defaultLimitMinor = 0;
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final List<Customer> customers =
        await DatabaseHelper.instance.getCustomers(search: _search.text);
    final int defaultLimit =
        await DatabaseHelper.instance.getCreditDefaultLimit();
    if (!mounted) return;
    setState(() {
      _customers = customers;
      _defaultLimitMinor = defaultLimit;
      _loading = false;
    });
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _load);
  }

  Future<void> _addInline() async {
    final Customer? created = await showCustomerEditSheet(context, null);
    if (created == null || !mounted) return;
    Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(spacing.lg, spacing.lg, spacing.lg, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l10n.sellCreditPickCustomer, style: type.titleLarge),
            SizedBox(height: spacing.sm),
            TextField(
              controller: _search,
              onChanged: _onSearch,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.customerSearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            SizedBox(height: spacing.sm),
            OutlinedButton.icon(
              onPressed: _addInline,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(l10n.customerAddInlineAction),
            ),
            SizedBox(height: spacing.sm),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_customers.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(spacing.md),
                      child: Text(
                        l10n.customersNoMatchesMessage,
                        style: type.bodyMedium
                            ?.copyWith(color: colors.onSurfaceMuted),
                      ),
                    )
                  else
                    for (final Customer customer in _customers)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(customer.name),
                        subtitle: Text(
                          customer.owes
                              ? l10n.customerOwesChip(formatMoney(
                                  Money.fromMinor(customer.balanceMinor)))
                              : l10n.customerBalanceClearHeading,
                          style: type.bodySmall
                              ?.copyWith(color: colors.onSurfaceMuted),
                        ),
                        trailing: Text(
                          formatMoney(Money.fromMinor(
                              customer.effectiveLimit(_defaultLimitMinor) -
                                  customer.balanceMinor)),
                          style: type.bodySmall
                              ?.copyWith(color: colors.onSurfaceMuted),
                        ),
                        onTap: () => Navigator.pop(context, customer),
                      ),
                ],
              ),
            ),
            SizedBox(height: spacing.md),
          ],
        ),
      ),
    );
  }
}
