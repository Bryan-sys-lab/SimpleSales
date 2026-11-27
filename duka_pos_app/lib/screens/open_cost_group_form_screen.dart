import 'package:material_ui/material_ui.dart';
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
  const OpenCostGroupFormScreen({super.key, this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<OpenCostGroupFormScreen> createState() =>
      _OpenCostGroupFormScreenState();
}

class _OpenCostGroupFormScreenState extends State<OpenCostGroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  final _costController = TextEditingController();
  String _poolType = 'lot';
  String _entryType = 'purchase';
  String _paidFrom = 'other';
  String? _units;
  bool _saving = false;

  DatabaseHelper get _db => DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = (existing['name'] as String?) ?? '';
      _noteController.text = (existing['note'] as String?) ?? '';
      final cost = existing['invested_minor'];
      if (cost is num) {
        _costController.text = (cost / 100).toStringAsFixed(2);
      }
      _poolType = (existing['pool_type'] as String?) ?? 'lot';
      _entryType = (existing['entry_type'] as String?) ?? 'purchase';
      _paidFrom = (existing['paid_from'] as String?) ?? 'other';
      _units = existing['units'] as String?;
    }
  }

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
          : Money.fromMajor(parseMoneyInput(costText) ?? 0);
      final existing = widget.existing;
      if (existing != null && existing['id'] is num) {
        await _db.updateCostPool(
          id: (existing['id'] as num).toInt(),
          name: _nameController.text.trim(),
          note: _noteController.text.trim(),
          poolType: _poolType,
          units: _units,
          initialCost: cost,
          entryType: _entryType,
          paidFrom: _paidFrom,
          description: _noteController.text.trim(),
        );
      } else {
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
          units: _units,
          description: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        );
      }
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context).openCostGroupCouldNotCreate(e))),
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

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: AdaptivePage(
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
                items: const <String>['lot', 'bale', 'rolling_stock']
                    .map((t) => DropdownMenuItem<String>(
                          value: t,
                          child: Text(t == 'rolling_stock'
                              ? 'Rolling stock'
                              : t[0].toUpperCase() + t.substring(1)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _poolType = v ?? 'lot'),
              ),
              SizedBox(height: spacing.md),
              DropdownButtonFormField<String?>(
                initialValue: _units,
                decoration: const InputDecoration(
                  labelText: 'Units (optional)',
                  helperText: 'e.g. kg, litre, bale, piece, each',
                ),
                items: const <String?>[
                  null,
                  'kg',
                  'litre',
                  'bale',
                  'piece',
                  'each',
                ]
                    .map((t) => DropdownMenuItem<String?>(
                          value: t,
                          child: Text(t ?? 'None'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _units = v),
              ),
              SizedBox(height: spacing.md),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              SizedBox(height: spacing.md),
              TextFormField(
                controller: _costController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Initial cost (optional)'),
                validator: (v) {
                  final String t = v?.trim() ?? '';
                  if (t.isEmpty) return null;
                  return parseMoneyInput(t) == null
                      ? 'Enter a valid amount'
                      : null;
                },
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
                    .map((t) =>
                        DropdownMenuItem<String>(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _entryType = v ?? 'purchase'),
              ),
              SizedBox(height: spacing.md),
              DropdownButtonFormField<String>(
                initialValue: _paidFrom,
                decoration: const InputDecoration(labelText: 'Paid from'),
                items: const <String>['other', 'till_cash', 'credit']
                    .map((t) =>
                        DropdownMenuItem<String>(value: t, child: Text(t)))
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
                     : Text(widget.existing != null
                         ? 'Save changes'
                         : AppLocalizations.of(context).createCostGroup),
              ),
              SizedBox(height: spacing.section),
            ],
          ),
        ),
      ),
    );
  }
}
