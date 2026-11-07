import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';

const double _openJobAddCostMaxWidth = 720;

class OpenJobAddCostScreen extends StatefulWidget {
  const OpenJobAddCostScreen({super.key, required this.jobId});

  final int jobId;

  @override
  State<OpenJobAddCostScreen> createState() => _OpenJobAddCostScreenState();
}

class _OpenJobAddCostScreenState extends State<OpenJobAddCostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _costType = 'materials';
  String _paidFrom = 'other';
  bool _saving = false;

  DatabaseHelper get _db => DatabaseHelper.instance;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final parsed = double.tryParse(_amountController.text.trim());
    if (parsed == null || parsed <= 0) return;
    setState(() => _saving = true);
    try {
      await _db.addJobCost(
        uuid: 'jobcost-${DateTime.now().microsecondsSinceEpoch}',
        jobId: widget.jobId,
        costType: _costType,
        amount: Money.fromMajor(parsed),
        paidFrom: _paidFrom,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add cost: $e')),
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
      maxContentWidth: _openJobAddCostMaxWidth,
      padding: PageGutter.of(context),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(height: spacing.section),
            Text(
              l10n.openJobAddCostTitle,
              style: AppTypography.of(context).headlineSmall,
            ),
            SizedBox(height: spacing.xl),
            DropdownButtonFormField<String>(
              initialValue: _costType,
              decoration: const InputDecoration(labelText: 'Cost type'),
              items: const <String>['materials', 'helper', 'transport', 'other']
                  .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _costType = v ?? 'materials'),
            ),
            SizedBox(height: spacing.md),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
              validator: (v) {
                final p = double.tryParse(v?.trim() ?? '');
                if (p == null || p <= 0) return 'Enter a positive amount';
                return null;
              },
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
            SizedBox(height: spacing.md),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
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
                  : const Text('Add cost'),
            ),
            SizedBox(height: spacing.section),
          ],
        ),
      ),
    );
  }
}
