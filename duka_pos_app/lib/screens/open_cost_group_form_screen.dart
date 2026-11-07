import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/layout/page.dart';
import '../utils/crypto_utils.dart';
import '../utils/money.dart';

const double _openCostGroupFormMaxWidth = 720;

class OpenCostGroupFormScreen extends StatefulWidget {
  const OpenCostGroupFormScreen({super.key});

  @override
  State<OpenCostGroupFormScreen> createState() => _OpenCostGroupFormScreenState();
}

class _OpenCostGroupFormScreenState extends State<OpenCostGroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  final _costController = TextEditingController();
  String _poolType = 'job';
  String _entryType = 'purchase';
  String _paidFrom = 'other';
  bool _saving = false;

  DatabaseHelper get _db => DatabaseHelper.instance;

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final costText = _costController.text.trim();
      final cost = costText.isEmpty
          ? null
          : Money.fromMajor(double.tryParse(costText) ?? 0);
      await _db.createCostPool(
        uuid: generateUuid(),
        name: _nameController.text.trim(),
        poolType: _poolType,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        initialCost: cost,
        entryType: _entryType,
        paidFrom: _paidFrom,
        description: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create cost group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);

    return AdaptivePage(
      scrollable: true,
      maxContentWidth: _openCostGroupFormMaxWidth,
      padding: PageGutter.of(context),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(height: spacing.section),
            Text(
              l10n.openCostGroupFormTitle,
              style: AppTypography.of(context).headlineSmall,
            ),
            SizedBox(height: spacing.xl),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Group name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name required' : null,
            ),
            SizedBox(height: spacing.md),
            DropdownButtonFormField<String>(
              initialValue: _poolType,
              decoration: const InputDecoration(labelText: 'Pool type'),
              items: const <String>['job', 'batch', 'general']
                  .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _poolType = v ?? 'job'),
            ),
            SizedBox(height: spacing.md),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            SizedBox(height: spacing.md),
            TextFormField(
              controller: _costController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Initial cost (optional)'),
            ),
            SizedBox(height: spacing.md),
            DropdownButtonFormField<String>(
              initialValue: _entryType,
              decoration: const InputDecoration(labelText: 'Entry type'),
              items: const <String>[
                'purchase',
                'transport',
                'packaging',
                'sorting',
                'other'
              ]
                  .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _entryType = v ?? 'purchase'),
            ),
            SizedBox(height: spacing.md),
            DropdownButtonFormField<String>(
              initialValue: _paidFrom,
              decoration: const InputDecoration(labelText: 'Paid from'),
              items: const <String>['other', 'till_cash', 'credit']
                  .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _paidFrom = v ?? 'other'),
            ),
            SizedBox(height: spacing.xl),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create cost group'),
            ),
            SizedBox(height: spacing.section),
          ],
        ),
      ),
    );
  }
}
