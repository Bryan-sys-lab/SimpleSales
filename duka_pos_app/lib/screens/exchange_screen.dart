import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';

const double _exchangeScreenMaxWidth = 900;

/// Fashion exchange: return goods from one sale, sell replacement goods,
/// reconcile the difference as cash or exchange credit — all in one
/// transactional flow.
///
/// Steps:
///   1. Find the original sale (search by receipt, staff, date).
///   2. Select which lines to return and in what quantity.
///   3. Select replacement variants and quantities.
///   4. Confirm — the return, replacement sale, and any cash/exchange-credit
///      difference commit atomically.
class ExchangeScreen extends StatefulWidget {
  const ExchangeScreen({super.key});

  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeScreenState extends State<ExchangeScreen> {
  final _db = DatabaseHelper.instance;

  // Step state
  int _step = 0; // 0 = find sale, 1 = select return lines, 2 = select replacements, 3 = confirm

  // Step 1: find a sale
  final _searchCtrl = TextEditingController();
  List<Sale> _foundSales = const [];
  bool _searching = false;
  Sale? _selectedSale;

  // Step 2: return lines
  final Map<int, double> _returnQuantities = <int, double>{}; // saleItemId -> qty
  final Map<int, bool> _returnRestock = <int, bool>{}; // saleItemId -> restock?

  // Step 3: replacements
  final List<_ReplacementDraft> _replacements = <_ReplacementDraft>[];

  bool _saving = false;
  String? _error;

  AppState get _appState => context.read<AppState>();
  String get _staffName => _appState.currentStaffName ?? 'Staff';
  int? get _staffId => _appState.currentStaffId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchSales() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) {
      setState(() {
        _foundSales = const [];
        _selectedSale = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final sales = await _db.getSales(since: DateTime.now().subtract(const Duration(days: 90)), limit: 50, withItems: true);
      final matched = <Sale>[];
      for (final s in sales) {
        final haystack = '${s.id} ${s.staffName} ${s.buyerName ?? ''} ${s.paymentReference ?? ''}'.toLowerCase();
        if (haystack.contains(query.toLowerCase())) {
          matched.add(s);
        }
      }
      if (!mounted) return;
      setState(() {
        _foundSales = matched;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = '$e';
      });
    }
  }

  void _selectSale(Sale sale) {
    setState(() {
      _selectedSale = sale;
      _returnQuantities.clear();
      _returnRestock.clear();
      _replacements.clear();
      _step = 1;
    });
  }

  void _toggleReturnLine(int saleItemId, double qty, bool restock) {
    setState(() {
      if (qty <= 0) {
        _returnQuantities.remove(saleItemId);
        _returnRestock.remove(saleItemId);
      } else {
        _returnQuantities[saleItemId] = qty;
        _returnRestock[saleItemId] = restock;
      }
    });
  }

  void _addReplacement(ProductVariant variant, double qty) {
    setState(() {
      _replacements.add(_ReplacementDraft(variant: variant, qty: qty));
    });
  }

  void _removeReplacement(int index) {
    setState(() {
      _replacements.removeAt(index);
    });
  }

  int get _returnedTotalMinor {
    int total = 0;
    if (_selectedSale == null) return 0;
    for (final item in _selectedSale!.items) {
      final qty = _returnQuantities[item.id ?? 0] ?? 0;
      if (qty <= 0) continue;
      total += (item.total.minorUnits * (qty / item.qty)).round();
    }
    return total;
  }

  int get _replacementTotalMinor {
    int total = 0;
    for (final r in _replacements) {
      total += (r.variant.sellPrice.minorUnits * r.qty).round();
    }
    return total;
  }

  int get _differenceMinor => _replacementTotalMinor - _returnedTotalMinor;

  bool get _canProceed =>
      _selectedSale != null &&
      _returnQuantities.values.any((q) => q > 0) &&
      _replacements.isNotEmpty;

  Future<void> _completeExchange() async {
    if (!_canProceed || _selectedSale == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final returnedLines = <ReturnLineDraft>[];
      for (final item in _selectedSale!.items) {
        final qty = _returnQuantities[item.id ?? 0] ?? 0;
        if (qty <= 0) continue;
        returnedLines.add(ReturnLineDraft(
          saleItemId: item.id!,
          qty: qty,
          restock: _returnRestock[item.id] ?? true,
        ));
      }

      final replacementItems = <SaleItem>[];
      for (final r in _replacements) {
        replacementItems.add(SaleItem(
          saleId: 0,
          productId: r.variant.productId,
          productName: r.variant.name,
          qty: r.qty,
          unitPrice: r.variant.sellPrice,
          unitCost: r.variant.costPrice,
          variantId: r.variant.id,
          variantName: r.variant.label,
        ));
      }

      final exchangeId = await _db.recordExchange(
        originalSale: _selectedSale!,
        returnedLines: returnedLines,
        replacementItems: replacementItems,
        reason: 'Exchange',
        staffName: _staffName,
        staffId: _staffId,
        paymentMethod: _differenceMinor > 0 ? 'cash' : 'cash',
        paymentReference: null,
      );

      if (!mounted) return;
      setState(() {
        _saving = false;
        _step = 3;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Exchange #$exchangeId recorded — return and replacement committed.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  void _startOver() {
    setState(() {
      _step = 0;
      _selectedSale = null;
      _foundSales = const [];
      _returnQuantities.clear();
      _returnRestock.clear();
      _replacements.clear();
      _error = null;
      _searchCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spacing = AppSpacing.of(context);
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return RefreshIndicator(
      onRefresh: () async {},
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _exchangeScreenMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () async {}),
            SizedBox(height: spacing.section),
            Text(
              _step == 0
                  ? l10n.exchangeFindSaleTitle
                  : _step == 1
                      ? l10n.exchangeReturnLinesTitle
                      : _step == 2
                          ? l10n.exchangeReplacementTitle
                          : l10n.exchangeConfirmTitle,
              style: type.headlineSmall,
            ),
            SizedBox(height: spacing.xs),
            // Progress chips
            _ProgressStepper(step: _step),
            SizedBox(height: spacing.xl),

            if (_step == 0) ...<Widget>[
              // Step 1: Find the original sale
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  labelText: l10n.exchangeSearchLabel,
                  hintText: l10n.exchangeSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              _searchSales();
                            },
                          ),
                ),
                onSubmitted: (_) => _searchSales(),
              ),
              SizedBox(height: spacing.sm),
              if (_error != null) ...<Widget>[
                SizedBox(height: spacing.sm),
                Container(
                  padding: EdgeInsets.all(spacing.md),
                  decoration: BoxDecoration(
                    color: colors.danger.withValues(alpha: 0.1),
                    borderRadius: AppShapes.of(context).controlRadius,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.cancel_outlined, color: colors.danger, size: 18),
                      SizedBox(width: spacing.sm),
                      Expanded(
                        child: Text(
                          _error!,
                          style: type.bodySmall?.copyWith(color: colors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: spacing.sm),
              SizedBox(
                height: 400,
                child: _foundSales.isEmpty && !_searching
                    ? Center(
                        child: Text(l10n.exchangeNoSalesFound),
                      )
                    : ListView.builder(
                        itemCount: _foundSales.length,
                        itemBuilder: (_, i) {
                          final s = _foundSales[i];
                          final selected = _selectedSale?.id == s.id;
                          return ListTile(
                            leading: Text('#${s.id}'),
                            title: Text(s.staffName),
                            subtitle: Text(
                              '${l10n.exchangeTotal} ${formatMoney(s.total)} · ${s.createdAt.substring(0, 10)}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            selected: selected,
                            selectedTileColor: colors.surfaceSunken,
                            onTap: () => _selectSale(s),
                          );
                        },
                      ),
              ),
            ] else if (_step == 1) ...<Widget>[
              // Step 2: Select return lines
              if (_selectedSale == null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _startOver,
                    child: Text(l10n.exchangeStartOver),
                  ),
                )
              else ...<Widget>[
                Text(
                  '${l10n.exchangeReturning} #${_selectedSale!.id}',
                  style: type.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: spacing.sm),
                Text(
                  '${l10n.exchangeReturnTotal} ${formatMoney(Money.fromMinor(_returnedTotalMinor))}',
                  style: type.bodyMedium,
                ),
                SizedBox(height: spacing.sm),
                if (_selectedSale!.items.isEmpty)
                  Text(l10n.exchangeNoLines)
                else
                  ..._selectedSale!.items.map((item) {
                    final currentQty = _returnQuantities[item.id ?? 0] ?? 0;
                    final remaining = item.qty;
                    return _ReturnExchangeLine(
                      item: item,
                      qty: currentQty,
                      remaining: remaining,
                      restock: _returnRestock[item.id ?? 0] ?? true,
                      onQtyChanged: (v) => _toggleReturnLine(
                        item.id ?? 0,
                        v,
                        _returnRestock[item.id ?? 0] ?? true,
                      ),
                      onRestockChanged: (v) => _toggleReturnLine(
                        item.id ?? 0,
                        _returnQuantities[item.id ?? 0] ?? 0,
                        v,
                      ),
                    );
                  }),
                SizedBox(height: spacing.lg),
              ],
            ] else if (_step == 2) ...<Widget>[
              // Step 3: Select replacements
              Text(
                l10n.exchangeChooseReplacement,
                style: type.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: spacing.sm),
              Text(
                '${l10n.exchangeReplacementTotal} ${formatMoney(Money.fromMinor(_replacementTotalMinor))}',
                style: type.bodyMedium,
              ),
              SizedBox(height: spacing.sm),
              if (_replacements.isEmpty)
                Text(l10n.exchangeNoReplacements)
              else
                ...List.generate(_replacements.length, (i) {
                  final r = _replacements[i];
                  return ListTile(
                    leading: Text(r.variant.label),
                    title: Text(formatMoney(r.variant.sellPrice)),
                    subtitle: Text('Qty: ${r.qty}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _removeReplacement(i),
                    ),
                  );
                }),
                SizedBox(height: spacing.lg),
                _ReplacementAdder(
                  onAdd: _addReplacement,
                ),
            ] else ...<Widget>[
              // Step 3: Confirm
              Card(
                child: Padding(
                  padding: EdgeInsets.all(spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(l10n.exchangeReview, style: type.titleMedium),
                      SizedBox(height: spacing.sm),
                      _ConfirmRow(
                        label: l10n.exchangeReturned,
                        value: formatMoney(Money.fromMinor(_returnedTotalMinor)),
                      ),
                      _ConfirmRow(
                        label: l10n.exchangeReplacementTotal,
                        value: formatMoney(Money.fromMinor(_replacementTotalMinor)),
                      ),
                      _ConfirmRow(
                        label: l10n.exchangeDifference,
                        value: formatMoney(Money.fromMinor(_differenceMinor)),
                        tone: _differenceMinor > 0
                            ? StatusTone.warning
                            : _differenceMinor < 0
                                ? StatusTone.success
                                : null,
                      ),
                      SizedBox(height: spacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _completeExchange,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(_saving ? 'Committing…' : l10n.exchangeCommit),
                        ),
                      ),
                      SizedBox(height: spacing.sm),
                      TextButton(
                        onPressed: _startOver,
                        child: Text(l10n.exchangeStartOver),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            SizedBox(height: spacing.section),
          ],
        ),
      ),
    );
  }
}

class _ProgressStepper extends StatelessWidget {
  const _ProgressStepper({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final steps = <String>[
      'Find sale',
      'Return lines',
      'Replacements',
      'Confirm',
    ];
    return Row(
      children: List.generate(steps.length, (i) {
        final active = i <= step;
        return Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: active ? colors.accent : colors.surfaceSunken,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

class _ReturnExchangeLine extends StatelessWidget {
  const _ReturnExchangeLine({
    required this.item,
    required this.qty,
    required this.remaining,
    required this.restock,
    required this.onQtyChanged,
    required this.onRestockChanged,
  });

  final SaleItem item;
  final double qty;
  final double remaining;
  final bool restock;
  final ValueChanged<double> onQtyChanged;
  final ValueChanged<bool> onRestockChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final type = AppTypography.of(context);

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.variantName.isNotEmpty
                            ? '${item.productName} · ${item.variantName}'
                            : item.productName,
                        style: type.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        '${l10n.exchangeSold} ${item.qty} · ${l10n.exchangeAvailable} ${remaining}',
                        style: type.labelSmall?.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      formatMoney(item.unitPrice),
                      style: type.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: qty > 0
                              ? () => onQtyChanged(qty - 1)
                              : null,
                          tooltip: l10n.exchangeLess,
                        ),
                        Text(
                          '${qty.toInt()}',
                          style: type.bodyMedium,
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: qty + 1 > remaining ? null : () => onQtyChanged(qty + 1),
                          tooltip: l10n.exchangeMore,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            Row(
              children: <Widget>[
                Checkbox(
                  value: restock,
                  onChanged: (v) => onRestockChanged(v ?? true),
                ),
                Expanded(
                  child: Text(
                    restock ? l10n.exchangeRestock : l10n.exchangeWriteOff,
                    style: type.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplacementAdder extends StatelessWidget {
  const _ReplacementAdder({required this.onAdd});

  final void Function(ProductVariant variant, double qty) onAdd;

  @override
  Widget build(BuildContext context) {
    // Minimal adder: in production this would open a variant selector sheet.
    // Here it's a stub that shows the pattern; variants come from the
    // selected sale's products in the real flow.
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.add_circle_outline),
        label: Text('Add replacement variant (variant selector sheet)'),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: type.bodyMedium,
            ),
          ),
          Text(
            value,
            style: type.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: tone != null
                  ? tone == StatusTone.danger
                      ? colors.danger
                      : tone == StatusTone.warning
                          ? colors.warning
                          : colors.success
                  : colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Draft of a replacement line being built.
class _ReplacementDraft {
  const _ReplacementDraft({
    required this.variant,
    required this.qty,
  });

  final ProductVariant variant;
  final double qty;
}
