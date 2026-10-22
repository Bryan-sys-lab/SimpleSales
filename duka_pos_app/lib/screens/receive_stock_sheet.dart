// Receiving stock: what arrived, and what it cost.
//
// ## WHAT THIS IS FOR
//
// "Record stock coming in with its cost, keep product costs current, and keep
// a purchase history. Today cost is a static field, so profit drifts from
// reality."
//
// The drift is the whole point. A bottle bought at 90 and a bottle bought at
// 110 are the same bottle and different money, and the profit on every later
// sale is measured against the price the shop actually paid. So a delivery
// does three things at once: it puts the stock on the shelf, it sets the
// product's cost to what was paid, and it records HOW the cost got there.
//
// ## THE ORDER THE PERSON MEETS
//
//   1. WHO — the supplier, optional. A delivery with no supplier named is
//      still a delivery, and the shop buys from people it has not written
//      down yet.
//   2. WHAT — the lines. Each line's cost starts at the cost the shop LAST
//      paid, because that is the number being replaced; the owner changes it
//      when this delivery is at a different price.
//   3. HOW MUCH — the total, and then it is posted.
//
// ## WHY IT IS A SHEET
//
// It is a panel over the stock, and it is dismissed by putting it away. The
// app's own routing is go_router, and this deliberately does not push a route
// for a thing that is a panel over a list.
//
// ## WHY THE SHEET READS NOTHING OF ITS OWN
//
// The products, the suppliers and the last costs are read by the CALLER, at
// the moment the sheet is opened. A widget that reads the database while it
// is building itself does its I/O in the middle of a build, which is slow,
// untestable, and — in a widget test — a hang.

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../utils/money.dart';

/// Opens the receive-stock flow.
///
/// [products] and [suppliers] are read by the caller, so the sheet does no
/// I/O of its own. [lastCostFor] answers what a product last cost.
Future<int?> showReceiveStockSheet(
  BuildContext context, {
  required List<Product> products,
  required List<Supplier> suppliers,
  required Future<Money?> Function(int productId) lastCostFor,
  required String staffName,
  int? staffId,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => ReceiveStockSheet(
      products: products,
      suppliers: suppliers,
      lastCostFor: lastCostFor,
      staffName: staffName,
      staffId: staffId,
    ),
  );
}

/// The receive-stock flow.
class ReceiveStockSheet extends StatefulWidget {
  const ReceiveStockSheet({
    required this.products,
    required this.suppliers,
    required this.lastCostFor,
    required this.staffName,
    this.staffId,
    super.key,
  });

  final List<Product> products;
  final List<Supplier> suppliers;

  /// What a product last cost, for the prefilled figure.
  final Future<Money?> Function(int productId) lastCostFor;

  final String staffName;
  final int? staffId;

  @override
  State<ReceiveStockSheet> createState() => _ReceiveStockSheetState();
}

class _ReceiveStockSheetState extends State<ReceiveStockSheet> {
  /// The lines, in the order they were added.
  final List<_ReceiptLine> _lines = <_ReceiptLine>[];

  int? _supplierId;
  final TextEditingController _supplierRef = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _supplierRef.dispose();
    super.dispose();
  }

  int get _totalMinor => _lines.fold<int>(
        0,
        (int sum, _ReceiptLine line) => sum + line.lineCostMinor,
      );

  Future<void> _addProduct(Product product) async {
    final int? productId = product.id;
    if (productId == null) return;
    // The cost starts at what the shop LAST paid: that is the number being
    // replaced, and it is the one the owner is most likely to keep.
    final Money? last = await widget.lastCostFor(productId);
    if (!mounted) return;
    setState(() {
      _lines.add(_ReceiptLine(
        productId: productId,
        productName: product.name,
        qty: 1,
        unitCost: last ?? product.costPrice,
      ));
    });
  }

  Future<void> _post() async {
    if (_lines.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).receiveNoLines);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final int receiptId = await DatabaseHelper.instance.postStockReceipt(
        lines: <StockReceiptLine>[
          for (final _ReceiptLine line in _lines)
            StockReceiptLine(
              productId: line.productId,
              productName: line.productName,
              qty: line.qty,
              unitCost: line.unitCost,
            ),
        ],
        supplierId: _supplierId,
        supplierRef:
            _supplierRef.text.trim().isEmpty ? null : _supplierRef.text.trim(),
        staffName: widget.staffName,
        staffId: widget.staffId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(receiptId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AppLocalizations.of(context).receiveFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final TextTheme type = AppTypography.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding:
                    EdgeInsets.fromLTRB(spacing.lg, spacing.lg, spacing.lg, 0),
                child: Text(l10n.receiveTitle, style: type.titleLarge),
              ),
              SizedBox(height: spacing.xs),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: Text(
                  l10n.receiveSubtitle,
                  style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
                ),
              ),
              SizedBox(height: spacing.md),

              // WHO.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l10n.receiveSupplierLabel, style: type.labelLarge),
                    SizedBox(height: spacing.xs),
                    DropdownButtonFormField<int?>(
                      initialValue: _supplierId,
                      isExpanded: true,
                      items: <DropdownMenuItem<int?>>[
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(l10n.receiveNoSupplier),
                        ),
                        for (final Supplier supplier in widget.suppliers)
                          if (supplier.id != null)
                            DropdownMenuItem<int?>(
                              value: supplier.id,
                              child: Text(supplier.name),
                            ),
                      ],
                      onChanged: (int? value) =>
                          setState(() => _supplierId = value),
                    ),
                    SizedBox(height: spacing.sm),
                    TextField(
                      controller: _supplierRef,
                      decoration: InputDecoration(
                        labelText: l10n.receiveSupplierRefLabel,
                        hintText: l10n.receiveSupplierRefHint,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.md),

              // WHAT.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(l10n.receiveLinesLabel, style: type.labelLarge),
                    SizedBox(height: spacing.xs),
                    for (var i = 0; i < _lines.length; i++)
                      _ReceiptLineRow(
                        line: _lines[i],
                        onChanged: (_ReceiptLine line) =>
                            setState(() => _lines[i] = line),
                        onRemoved: () => setState(() => _lines.removeAt(i)),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _pickProduct(),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.receiveAddProductAction),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...<Widget>[
                SizedBox(height: spacing.md),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                  child: PersistentBanner(
                    tone: StatusTone.danger,
                    icon: Icons.cancel_outlined,
                    message: _error!,
                  ),
                ),
              ],
              SizedBox(height: spacing.lg),

              // HOW MUCH, and the button.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: shapes.cardRadius,
                  ),
                  padding: EdgeInsets.all(spacing.md),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(l10n.receiveTotalLabel,
                                style: type.bodyMedium),
                            Text(
                              formatMoney(Money.fromMinor(_totalMinor)),
                              style: type.titleLarge,
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: _saving ? null : _post,
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(l10n.receivePostAction),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: spacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  /// The product picker.
  Future<void> _pickProduct() async {
    final Product? picked = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _ProductPicker(
        products: widget.products,
        alreadyOn: <int>{
          for (final _ReceiptLine line in _lines) line.productId,
        },
      ),
    );
    if (picked == null) return;
    await _addProduct(picked);
  }
}

/// One line of the delivery, as the person is filling it in.
class _ReceiptLine {
  _ReceiptLine({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.unitCost,
  });

  final int productId;
  final String productName;
  final double qty;
  final Money unitCost;

  int get lineCostMinor => (unitCost.minorUnits * qty).round();
}

/// One line of the delivery, editable.
class _ReceiptLineRow extends StatelessWidget {
  const _ReceiptLineRow({
    required this.line,
    required this.onChanged,
    required this.onRemoved,
  });

  final _ReceiptLine line;
  final ValueChanged<_ReceiptLine> onChanged;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Container(
      margin: EdgeInsets.only(bottom: spacing.sm),
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: AppShapes.of(context).controlRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(line.productName, style: type.bodyLarge),
              ),
              IconButton(
                onPressed: onRemoved,
                icon: const Icon(Icons.close),
                tooltip: l10n.receiveRemoveLineAction,
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  initialValue: _formatQty(line.qty),
                  decoration: InputDecoration(
                    labelText: l10n.receiveQtyLabel,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (String value) {
                    final double qty = double.tryParse(value) ?? line.qty;
                    onChanged(_ReceiptLine(
                      productId: line.productId,
                      productName: line.productName,
                      qty: qty,
                      unitCost: line.unitCost,
                    ));
                  },
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: TextFormField(
                  initialValue: _formatQty(line.unitCost.minorUnits / 100),
                  decoration: InputDecoration(
                    labelText: l10n.receiveUnitCostLabel,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (String value) {
                    final double amount = double.tryParse(value) ??
                        line.unitCost.minorUnits / 100;
                    onChanged(_ReceiptLine(
                      productId: line.productId,
                      productName: line.productName,
                      qty: line.qty,
                      unitCost: Money.fromMinor((amount * 100).round()),
                    ));
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.xs),
          Text(
            l10n.receiveLineTotal(
                formatMoney(Money.fromMinor(line.lineCostMinor))),
            style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }

  /// A number, without a trailing ".0" on the whole numbers.
  static String _formatQty(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(2);
  }
}

/// The product picker: what arrived.
class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.products, required this.alreadyOn});

  final List<Product> products;

  /// The products already on the delivery.
  ///
  /// A product can be on a delivery twice — two cases of the same beer, at
  /// two prices — so the picker does not hide them. It says how many are
  /// already there instead, which is the fact the person needs.
  final Set<int> alreadyOn;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    final String query = _query.trim().toLowerCase();
    final List<Product> matches = query.isEmpty
        ? widget.products
        : widget.products
            .where((Product p) => p.name.toLowerCase().contains(query))
            .toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(spacing.md),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.receiveSearchLabel,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (String value) => setState(() => _query = value),
              ),
            ),
            Flexible(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (BuildContext context, int index) {
                  final Product product = matches[index];
                  final int times = widget.alreadyOn
                      .where(
                        (int id) => id == product.id,
                      )
                      .length;
                  return ListTile(
                    title: Text(product.name),
                    subtitle:
                        times > 0 ? Text(l10n.receiveAlreadyOn(times)) : null,
                    onTap: () => Navigator.of(context).pop(product),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
