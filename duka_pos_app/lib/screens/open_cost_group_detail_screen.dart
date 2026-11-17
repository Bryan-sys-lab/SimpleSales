import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../widgets/backup_reminder_banner.dart';

const double _openCostGroupDetailMaxWidth = 900;

/// One cost group's detail: info, investment, allocations, remaining balance,
/// movement history.
class OpenCostGroupDetailScreen extends StatefulWidget {
  const OpenCostGroupDetailScreen({super.key, required this.poolId});

  final int poolId;

  @override
  State<OpenCostGroupDetailScreen> createState() =>
      _OpenCostGroupDetailScreenState();
}

class _OpenCostGroupDetailScreenState extends State<OpenCostGroupDetailScreen> {
  Map<String, dynamic>? _pool;
  List<Map<String, dynamic>> _entries = const [];
  bool _loading = true;

  DatabaseHelper get _db => DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pools = await _db.getCostPools();
      final pool = pools.firstWhere(
        (p) => (p['id'] as num).toInt() == widget.poolId,
        orElse: () => <String, dynamic>{},
      );
      final entries = await _db.getCostPoolEntries(widget.poolId);
      if (!mounted) return;
      setState(() {
        _pool = pool;
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _reloadStock() async {
    final session = context.read<AppState>();
    final canManage = session.isOwnerSession ||
        (session.hasPermission(PermissionKey.receiveStock) &&
            session.hasPermission(PermissionKey.viewCost));
    if (!canManage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You do not have permission to reload stock')),
      );
      return;
    }
    final products = await _db.getProducts();
    if (!mounted) return;
    final quantity = TextEditingController();
    final unitCost = TextEditingController();
    final supplierRef = TextEditingController();
    Product? product =
        products.where((item) => item.costPoolId == widget.poolId).firstOrNull;
    var paidFrom = 'other';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Reload stock'),
          content: SingleChildScrollView(
            child: FormFieldGroup(
              children: <Widget>[
                DropdownButtonFormField<Product>(
                  initialValue: product,
                  decoration: const InputDecoration(labelText: 'Stock item'),
                  items: <DropdownMenuItem<Product>>[
                    for (final item in products)
                      DropdownMenuItem<Product>(
                        value: item,
                        child: Text(item.name),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() => product = value),
                ),
                TextField(
                  controller: quantity,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                TextField(
                  controller: unitCost,
                  decoration:
                      const InputDecoration(labelText: 'Unit cost (KES)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                DropdownButtonFormField<String>(
                  initialValue: paidFrom,
                  decoration:
                      const InputDecoration(labelText: 'Payment source'),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(
                        value: 'till_cash', child: Text('Till cash')),
                    DropdownMenuItem(
                        value: 'credit', child: Text('Supplier credit')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => paidFrom = value ?? 'other'),
                ),
                TextField(
                  controller: supplierRef,
                  decoration:
                      const InputDecoration(labelText: 'Supplier reference'),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(AppLocalizations.of(context).save),
            ),
          ],
        ),
      ),
    );
    final selected = product;
    final qty = double.tryParse(quantity.text.trim());
    final cost = parseMoneyInput(unitCost.text.trim());
    final reference = supplierRef.text.trim();
    if (!mounted) return;
    final staff = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    quantity.dispose();
    unitCost.dispose();
    supplierRef.dispose();
    if (result != true ||
        selected?.id == null ||
        qty == null ||
        qty <= 0 ||
        cost == null ||
        cost < 0 ||
        !mounted) {
      return;
    }
    try {
      await _db.reloadCostPoolStock(
        poolId: widget.poolId,
        productId: selected!.id!,
        qty: qty,
        unitCost: Money.fromMajor(cost),
        paidFrom: paidFrom,
        supplierRef: reference.isEmpty ? null : reference,
        staffName: staff.currentStaffName ?? staff.owner?.name ?? 'Owner',
        staffId: staff.currentStaffId,
      );
      if (mounted) {
        await _load();
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Stock reloaded')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  int _investedMinor() => (_pool?['invested_minor'] as num?)?.toInt() ?? 0;
  int _recoveredMinor() => (_pool?['recovered_minor'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);

    if (_loading) {
      return AdaptivePage(
        maxContentWidth: _openCostGroupDetailMaxWidth,
        padding: PageGutter.of(context),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_pool == null || _pool!.isEmpty) {
      return AdaptivePage(
        maxContentWidth: _openCostGroupDetailMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () => performBackup(context)),
            SizedBox(height: spacing.section),
            Text(
              l10n.openCostGroupDetailNotFound,
              style: AppTypography.of(context).headlineSmall,
            ),
          ],
        ),
      );
    }

    final invested = Money.fromMinor(_investedMinor());
    final recovered = Money.fromMinor(_recoveredMinor());
    final remaining = Money.fromMinor(
      invested.minorUnits - recovered.minorUnits,
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _openCostGroupDetailMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () => performBackup(context)),
            SizedBox(height: spacing.section),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _pool!['name'] as String,
                        style: AppTypography.of(context).headlineSmall,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        _pool!['note'] as String? ??
                            l10n.openCostGroupDetailNoNote,
                        style: AppTypography.of(context)
                            .bodyMedium
                            ?.copyWith(color: colors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  tone: remaining.minorUnits > 0
                      ? StatusTone.warning
                      : StatusTone.success,
                  text: remaining.minorUnits > 0
                      ? l10n.openCostGroupDetailHasRemaining
                      : l10n.openCostGroupDetailFullyAllocated,
                ),
              ],
            ),
            SizedBox(height: spacing.xl),
            FilledButton.icon(
              onPressed: _reloadStock,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Reload stock'),
            ),
            SizedBox(height: spacing.lg),
            _DetailSection(
              title: l10n.openCostGroupDetailInvestment,
              children: <Widget>[
                _DetailRow(
                  label: l10n.openCostGroupDetailInitialInvestment,
                  value: formatMoney(invested),
                ),
                _DetailRow(
                  label: l10n.openCostGroupDetailAllocated,
                  value: formatMoney(recovered),
                ),
                _DetailRow(
                  label: l10n.openCostGroupDetailRemaining,
                  value: formatMoney(remaining),
                  tone: remaining.minorUnits > 0
                      ? StatusTone.warning
                      : StatusTone.success,
                ),
              ],
            ),
            SizedBox(height: spacing.lg),
            _DetailSection(
              title: l10n.openCostGroupDetailMovementHistory,
              children: <Widget>[
                if (_entries.isEmpty)
                  Text(
                    l10n.openCostGroupDetailNoMovements,
                    style: AppTypography.of(context)
                        .labelSmall
                        ?.copyWith(color: colors.onSurfaceMuted),
                  )
                else
                  for (final entry in _entries)
                    _MovementRow(
                      label: entry['description'] as String? ??
                          l10n.openCostGroupDetailEntry,
                      amount: Money.fromMinor(
                        (entry['amount_minor'] as num?)?.toInt() ?? 0,
                      ),
                      when: entry['created_at'] as String? ?? '',
                    ),
              ],
            ),
            SizedBox(height: spacing.section),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final type = AppTypography.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: type.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: spacing.sm),
        ...children,
        SizedBox(height: spacing.lg),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.tone,
  });

  final String label;
  final String value;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: type.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
            ),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                Text(
                  value,
                  style: type.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: tone != null
                        ? (tone == StatusTone.danger
                            ? colors.danger
                            : colors.warning)
                        : colors.onSurface,
                  ),
                ),
                if (tone != null) ...<Widget>[
                  SizedBox(width: spacing.sm),
                  StatusChip(
                    tone: tone!,
                    text: tone!.label,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({
    required this.label,
    required this.amount,
    required this.when,
  });

  final String label;
  final Money amount;
  final String when;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: type.bodyMedium,
                ),
                SizedBox(height: spacing.xs),
                Text(
                  when,
                  style:
                      type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(amount),
            style: type.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
