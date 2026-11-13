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
  bool _loading = false;
  bool _isEdit = false;
  int? _selectedPoolId;
  List<Map<String, dynamic>> _pools = const [];

  DatabaseHelper get _db => DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    if (widget.jobId != null) {
      _isEdit = true;
      _loading = true;
      _load(widget.jobId!);
    } else {
      _loadPools();
    }
  }

  Future<void> _load(int id) async {
    try {
      final rows = await _db.database.then((d) =>
          d.query('jobs', where: 'id = ?', whereArgs: [id], limit: 1));
      if (rows.isEmpty || !mounted) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final r = rows.first;
      _titleController.text = (r['title'] as String?) ?? '';
      _customerController.text = (r['customer_name'] as String?) ?? '';
      _selectedPoolId = (r['cost_pool_id'] as num?)?.toInt();
      final q = r['quote_minor'];
      if (q != null) {
        final minor = q is int ? q : (q as num).toInt();
        _quoteController.text = (minor / 100.0).toStringAsFixed(2);
      }
      await _loadPools();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPools() async {
    try {
      final pools = await _db.getCostPools();
      if (!mounted) return;
      setState(() => _pools = pools);
    } catch (_) {}
  }

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
      if (_isEdit && widget.jobId != null) {
        await _db.updateJob(
          id: widget.jobId!,
          title: _titleController.text.trim(),
          customerName: _customerController.text.trim().isEmpty
              ? null
              : _customerController.text.trim(),
          finalPriceMinor: quote?.minorUnits,
        );
      } else {
        await _db.createJob(
          uuid: generateUuid(),
          title: _titleController.text.trim(),
          customerName: _customerController.text.trim().isEmpty
              ? null
              : _customerController.text.trim(),
          quote: quote,
          costPoolId: _selectedPoolId,
        );
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).openJobFormCouldNotCreate(e))),
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

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
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
              _isEdit ? 'Edit job' : l10n.openJobFormTitle,
              style: AppTypography.of(context).headlineSmall,
            ),
            SizedBox(height: spacing.xl),
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(labelText: l10n.openJobFormJobTitleLabel),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l10n.openJobFormTitleRequired : null,
            ),
            SizedBox(height: spacing.md),
            TextFormField(
              controller: _customerController,
              decoration: InputDecoration(labelText: l10n.openJobFormCustomerLabel),
            ),
            SizedBox(height: spacing.md),
            TextFormField(
              controller: _quoteController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l10n.openJobFormQuoteLabel),
            ),
            SizedBox(height: spacing.md),
            DropdownButtonFormField<int?>(
              initialValue: _selectedPoolId,
              decoration: const InputDecoration(labelText: 'Cost group (optional)'),
              items: <DropdownMenuItem<int?>>[
                const DropdownMenuItem<int?>(value: null, child: Text('None')),
                for (final pool in _pools)
                  DropdownMenuItem<int?>(
                    value: (pool['id'] as num).toInt(),
                    child: Text(pool['name'] as String? ?? 'Untitled group'),
                  ),
              ],
              onChanged: (v) => setState(() => _selectedPoolId = v),
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
                  : Text(_isEdit ? l10n.openJobFormSaveAction : l10n.openJobFormCreateAction),
            ),
            SizedBox(height: spacing.section),
          ],
        ),
      ),
    );
  }
}
