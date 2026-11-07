import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/crypto_utils.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';

const double _openJobFormMaxWidth = 720;

class OpenJobFormScreen extends StatefulWidget {
  const OpenJobFormScreen({super.key, this.jobId});

  final int? jobId;

  @override
  State<OpenJobFormScreen> createState() => _OpenJobFormScreenState();
}

class _OpenJobFormScreenState extends State<OpenJobFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _customerController = TextEditingController();
  final _quoteController = TextEditingController();
  bool _saving = false;

  DatabaseHelper get _db => DatabaseHelper.instance;

  @override
  void dispose() {
    _titleController.dispose();
    _customerController.dispose();
    _quoteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final quoteText = _quoteController.text.trim();
      final quote = quoteText.isEmpty
          ? null
          : Money.fromMajor(double.tryParse(quoteText) ?? 0);
      await _db.createJob(
        uuid: generateUuid(),
        title: _titleController.text.trim(),
        customerName: _customerController.text.trim().isEmpty
            ? null
            : _customerController.text.trim(),
        quote: quote,
      );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create job: $e')),
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
      maxContentWidth: _openJobFormMaxWidth,
      padding: PageGutter.of(context),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(height: spacing.section),
            Text(
              l10n.openJobFormTitle,
              style: AppTypography.of(context).headlineSmall,
            ),
            SizedBox(height: spacing.xl),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Job title'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title required' : null,
            ),
            SizedBox(height: spacing.md),
            TextFormField(
              controller: _customerController,
              decoration: const InputDecoration(labelText: 'Customer (optional)'),
            ),
            SizedBox(height: spacing.md),
            TextFormField(
              controller: _quoteController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quoted amount (optional)'),
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
                  : const Text('Create job'),
            ),
            SizedBox(height: spacing.section),
          ],
        ),
      ),
    );
  }
}
