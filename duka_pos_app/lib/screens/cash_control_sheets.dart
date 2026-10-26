import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../utils/money.dart';
import '../utils/text_input.dart';
import '../utils/crypto_utils.dart';
import '../services/app_state.dart';
import '../services/cash_control_policy.dart';
import '../services/roles.dart';
import '../ui/dialogs/manager_approval_sheet.dart';

Future<bool> showExpenseSheet(
  BuildContext context, {
  required String staffName,
  int? staffId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExpenseSheet(staffName: staffName, staffId: staffId),
  ).then((value) => value ?? false);
}

Future<bool> showExpensePaymentSheet(
  BuildContext context, {
  required int expenseId,
  required int remainingMinor,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExpensePaymentSheet(
      expenseId: expenseId,
      remainingMinor: remainingMinor,
    ),
  ).then((value) => value ?? false);
}

Future<bool> showTillMovementSheet(
  BuildContext context, {
  required int shiftId,
  required String staffName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TillMovementSheet(shiftId: shiftId, staffName: staffName),
  ).then((value) => value ?? false);
}

class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet({required this.staffName, this.staffId});
  final String staffName;
  final int? staffId;

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  List<Map<String, dynamic>> _categories = const [];
  int? _categoryId;
  String _paidFrom = 'till_cash';
  bool _saving = false;
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final categories = await DatabaseHelper.instance.getExpenseCategories();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _categoryId = categories.isEmpty ? null : categories.first['id'] as int;
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = parseUserNumber(_amount.text);
    if (value == null || value <= 0 || _categoryId == null || _saving) return;
    setState(() => _saving = true);
    try {
      final state = context.read<AppState>();
      Staff? approver;
      final modeRequiresApproval = state.permissionMode(
            PermissionKey.recordExpense,
          ) ==
          PermissionMode.approval;
      if (!state.isOwnerSession &&
          (modeRequiresApproval || state.role == ShopRole.cashier)) {
        final limit =
            await DatabaseHelper.instance.getExpenseApprovalLimitMinor();
        if (modeRequiresApproval ||
            expenseApprovalRequired(
              amountMinor: Money.fromMajor(value).minorUnits,
              limitMinor: limit,
            )) {
          if (mounted) {
            approver = await showManagerApprovalSheet(
              context,
              purpose:
                  'Approve this ${_paidFrom == 'till_cash' ? 'till' : 'other-funds'} payout.',
            );
          }
          if (approver == null) {
            if (mounted) setState(() => _saving = false);
            return;
          }
        }
      }
      final uuid = generateUuid();
      await DatabaseHelper.instance.recordExpense(
        uuid: uuid,
        categoryId: _categoryId!,
        amount: Money.fromMajor(value),
        paidFrom: _paidFrom,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        staffName: widget.staffName,
        staffId: widget.staffId,
        approvedBy: approver?.id,
        photoPath: _photoPath,
      );
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString())),
      );
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      imageQuality: 82,
    );
    if (picked == null || !mounted) {
      return;
    }
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory('${directory.path}/expense_photos');
    await folder.create(recursive: true);
    final target = File('${folder.path}/${generateUuid()}.jpg');
    await File(picked.path).copy(target.path);
    if (mounted) {
      setState(
        () => _photoPath = 'expense_photos/${target.uri.pathSegments.last}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);
    return _SheetFrame(
      title: l10n.expensePayOutTitle,
      subtitle: l10n.expensePayOutSubtitle,
      children: <Widget>[
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(userNumberPattern),
          ],
          decoration: InputDecoration(labelText: l10n.expenseAmountLabel),
        ),
        SizedBox(height: spacing.sm),
        OutlinedButton.icon(
          onPressed: _saving ? null : _pickPhoto,
          icon: Icon(
              _photoPath == null ? Icons.camera_alt_outlined : Icons.check),
          label: Text(
              _photoPath == null ? 'Add receipt photo' : 'Receipt photo added'),
        ),
        SizedBox(height: spacing.sm),
        DropdownButtonFormField<int>(
          initialValue: _categoryId,
          isExpanded: true,
          items: <DropdownMenuItem<int>>[
            for (final row in _categories)
              DropdownMenuItem<int>(
                value: row['id'] as int,
                child: Text(row['name'] as String),
              ),
          ],
          onChanged:
              _saving ? null : (value) => setState(() => _categoryId = value),
          decoration: InputDecoration(labelText: l10n.expenseCategoryLabel),
        ),
        SizedBox(height: spacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _paidFrom,
          isExpanded: true,
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: 'till_cash',
              child: Text('Till cash'),
            ),
            DropdownMenuItem<String>(
              value: 'other',
              child: Text('Other funds'),
            ),
            DropdownMenuItem<String>(
              value: 'payable',
              child: Text('Pay later'),
            ),
          ],
          onChanged: _saving
              ? null
              : (value) {
                  if (value != null) setState(() => _paidFrom = value);
                },
          decoration: const InputDecoration(labelText: 'Paid from'),
        ),
        SizedBox(height: spacing.sm),
        TextField(
          controller: _note,
          maxLines: 2,
          decoration: InputDecoration(labelText: l10n.expenseNoteLabel),
        ),
        SizedBox(height: spacing.md),
        FilledButton.icon(
          onPressed: _categoryId == null || _saving ? null : _save,
          icon: const Icon(Icons.check),
          label: Text(l10n.expenseSaveAction),
        ),
      ],
    );
  }
}

class _ExpensePaymentSheet extends StatefulWidget {
  const _ExpensePaymentSheet({
    required this.expenseId,
    required this.remainingMinor,
  });

  final int expenseId;
  final int remainingMinor;

  @override
  State<_ExpensePaymentSheet> createState() => _ExpensePaymentSheetState();
}

class _ExpensePaymentSheetState extends State<_ExpensePaymentSheet> {
  late final TextEditingController _amount;
  final TextEditingController _reference = TextEditingController();
  String _method = 'cash';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: Money.fromMinor(widget.remainingMinor).asMajor.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = parseUserNumber(_amount.text);
    if (value == null || value <= 0 || _saving) return;
    setState(() => _saving = true);
    try {
      await DatabaseHelper.instance.recordExpensePayment(
        uuid: generateUuid(),
        expenseId: widget.expenseId,
        amount: Money.fromMajor(value),
        paymentMethod: _method,
        reference:
            _reference.text.trim().isEmpty ? null : _reference.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    return _SheetFrame(
      title: 'Pay expense',
      subtitle:
          'Remaining payable: ${formatMoney(Money.fromMinor(widget.remainingMinor))}',
      children: <Widget>[
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(userNumberPattern),
          ],
          decoration: const InputDecoration(labelText: 'Payment amount'),
        ),
        SizedBox(height: spacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _method,
          isExpanded: true,
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem(value: 'cash', child: Text('Cash')),
            DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa')),
            DropdownMenuItem(
                value: 'bank_transfer', child: Text('Bank transfer')),
          ],
          onChanged:
              _saving ? null : (value) => setState(() => _method = value!),
          decoration: const InputDecoration(labelText: 'Payment method'),
        ),
        SizedBox(height: spacing.sm),
        TextField(
          controller: _reference,
          decoration: const InputDecoration(labelText: 'Reference (optional)'),
        ),
        SizedBox(height: spacing.md),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check),
          label: const Text('Record payment'),
        ),
      ],
    );
  }
}

class _TillMovementSheet extends StatefulWidget {
  const _TillMovementSheet({required this.shiftId, required this.staffName});
  final int shiftId;
  final String staffName;

  @override
  State<_TillMovementSheet> createState() => _TillMovementSheetState();
}

class _TillMovementSheetState extends State<_TillMovementSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _type = 'cash_in';
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = parseUserNumber(_amount.text);
    if (value == null || value <= 0 || _saving) return;
    setState(() => _saving = true);
    try {
      final amount = Money.fromMajor(_type == 'cash_in' ? value : -value);
      await DatabaseHelper.instance.recordTillMovement(
        uuid: generateUuid(),
        shiftId: widget.shiftId,
        movementType: _type,
        amount: amount,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        staffName: widget.staffName,
      );
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);
    return _SheetFrame(
      title: l10n.tillMovementTitle,
      subtitle: l10n.tillMovementSubtitle,
      children: <Widget>[
        DropdownButtonFormField<String>(
          initialValue: _type,
          isExpanded: true,
          items: <DropdownMenuItem<String>>[
            DropdownMenuItem(
                value: 'cash_in', child: Text(l10n.tillCashInAction)),
            DropdownMenuItem(
                value: 'cash_drop', child: Text(l10n.tillCashDropAction)),
          ],
          onChanged: _saving ? null : (value) => setState(() => _type = value!),
          decoration: InputDecoration(labelText: l10n.tillMovementTypeLabel),
        ),
        SizedBox(height: spacing.sm),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(userNumberPattern),
          ],
          decoration: InputDecoration(labelText: l10n.expenseAmountLabel),
        ),
        SizedBox(height: spacing.sm),
        TextField(
          controller: _note,
          maxLines: 2,
          decoration: InputDecoration(labelText: l10n.expenseNoteLabel),
        ),
        SizedBox(height: spacing.md),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check),
          label: Text(l10n.tillMovementSaveAction),
        ),
      ],
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame(
      {required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.lg,
        spacing.lg,
        spacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title, style: AppTypography.of(context).titleLarge),
              SizedBox(height: spacing.xs),
              Text(subtitle),
              SizedBox(height: spacing.md),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
