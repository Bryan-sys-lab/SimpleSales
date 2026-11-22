import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
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
  const OpenCostGroupDetailScreen({
    super.key,
    required this.poolId,
    this.loadPools,
    this.loadProducts,
    this.loadEntries,
  });

  final int poolId;
  final Future<List<Map<String, dynamic>>> Function()? loadPools;
  final Future<List<Product>> Function()? loadProducts;
  final Future<List<Map<String, dynamic>>> Function(int poolId)? loadEntries;

  @override
  State<OpenCostGroupDetailScreen> createState() =>
      _OpenCostGroupDetailScreenState();
}

class _OpenCostGroupDetailScreenState extends State<OpenCostGroupDetailScreen> {
  Map<String, dynamic>? _pool;
  List<Map<String, dynamic>> _entries = const [];
  List<Product> _products = const [];
  bool _loading = true;
  bool _loadError = false;

  DatabaseHelper get _db => DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final pools = await (widget.loadPools?.call() ?? _db.getCostPools());
      final products = await (widget.loadProducts?.call() ?? _db.getProducts());
      final pool = pools.firstWhere(
        (p) => (p['id'] as num).toInt() == widget.poolId,
        orElse: () => <String, dynamic>{},
      );
      final entries = await (widget.loadEntries?.call(widget.poolId) ??
          _db.getCostPoolEntries(widget.poolId));
      if (!mounted) return;
      setState(() {
        _pool = pool;
        _entries = entries;
        _products = products
            .where((Product item) => item.costPoolId == widget.poolId)
            .toList();
        _loading = false;
      });
    } catch (error, stack) {
      debugPrint('Could not load cost group detail: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
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
    final List<Product> products;
    try {
      products = (await _db.getProducts())
          .where((Product item) => item.costPoolId == widget.poolId)
          .toList();
    } catch (error, stack) {
      debugPrint(
          'Could not load products for cost-pool reload: $error\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).openCostGroupDetailLoadFailed,
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).openCostGroupDetailNoProductsForReload,
          ),
        ),
      );
      return;
    }
    final quantity = TextEditingController();
    final unitCost = TextEditingController();
    final supplierRef = TextEditingController();
    Product? product = products.firstOrNull;
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

    if (_loadError) {
      return AdaptivePage(
        maxContentWidth: _openCostGroupDetailMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () => performBackup(context)),
            SizedBox(height: spacing.section),
            PersistentBanner(
              message: l10n.openCostGroupDetailLoadFailed,
              icon: Icons.error_outline,
              actionLabel: l10n.openCostGroupDetailRetry,
              onAction: _load,
              tone: StatusTone.danger,
            ),
          ],
        ),
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
                      ? StatusTone.neutral
                      : StatusTone.success,
                  text: remaining.minorUnits > 0
                      ? l10n.openCostGroupDetailHasRemaining
                      : l10n.openCostGroupDetailFullyAllocated,
                ),
              ],
            ),
            SizedBox(height: spacing.xl),
            FilledButton.icon(
              onPressed: _products.isEmpty ? null : _reloadStock,
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
                      ? StatusTone.neutral
                      : StatusTone.success,
                ),
              ],
            ),
            SizedBox(height: spacing.lg),
            _DetailSection(
              title: l10n.openCostGroupDetailLinkedItems,
              children: <Widget>[
                if (_products.isEmpty)
                  Text(
                    l10n.openCostGroupDetailNoLinkedItems,
                    style: AppTypography.of(context)
                        .labelSmall
                        ?.copyWith(color: colors.onSurfaceMuted),
                  )
                else
                  for (final Product item in _products)
                    _PoolProductRow(product: item),
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

class _PoolProductRow extends StatelessWidget {
  const _PoolProductRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final String stock =
        '${product.stockQty.toStringAsFixed(2)} ${product.unit.wire}';

    return Semantics(
      label: '${product.name}, $stock, ${formatMoney(product.sellPrice)}',
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: spacing.xs),
        child: Row(
          children: <Widget>[
            Icon(Icons.inventory_2_outlined, color: colors.onSurfaceMuted),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    product.name,
                    style: type.bodyMedium?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    stock,
                    style: type.labelSmall?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: spacing.sm),
            Text(
              formatMoney(product.sellPrice),
              style: type.labelMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
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

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(label: title),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              spacing.md,
              0,
              spacing.md,
              spacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
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
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: type.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
            ),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: type.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: tone?.color(colors) ?? colors.onSurface,
              ),
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
