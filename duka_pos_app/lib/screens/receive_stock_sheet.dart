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
import '../utils/kenya_phone.dart';
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
  String costingMode = 'weighted_average',
  ReceiveDraftSnapshot? draft,
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
      costingMode: costingMode,
      draft: draft,
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
    this.costingMode = 'weighted_average',

    /// Resumes a session the app killed: the draft's supplier, reference and
    /// lines, so a half-scanned delivery loses nothing. The sheet reads none
    /// of its own — the CALLER read the draft and passed it in.
    this.draft,
    super.key,
  }) : assert(costingMode == 'weighted_average' || costingMode == 'last_cost');

  final List<Product> products;
  final List<Supplier> suppliers;

  /// What a product last cost, for the prefilled figure.
  final Future<Money?> Function(int productId) lastCostFor;

  final String staffName;
  final int? staffId;
  final ReceiveDraftSnapshot? draft;
  final String costingMode;

  @override
  State<ReceiveStockSheet> createState() => _ReceiveStockSheetState();
}

/// What a receive-session draft hands back to the sheet.
class ReceiveDraftSnapshot {
  const ReceiveDraftSnapshot({
    this.supplierId,
    this.supplierRef,
    required this.lines,
  });

  final int? supplierId;
  final String? supplierRef;
  final List<StockReceiptLine> lines;

  bool get isEmpty =>
      lines.isEmpty && supplierId == null && supplierRef == null;

  /// Read from the database helper's draft payload.
  static ReceiveDraftSnapshot? fromJson(Map<String, dynamic> json) {
    final lines = <StockReceiptLine>[
      for (final line in (json['lines'] as List<dynamic>? ?? <dynamic>[]))
        if (line is Map<String, dynamic>)
          StockReceiptLine(
            productId: (line['product_id'] as num).toInt(),
            productName: line['product_name'] as String? ?? '',
            qty: (line['qty'] as num?)?.toDouble() ?? 0,
            unitCost: Money.fromMinor(
                (line['unit_cost_minor'] as num?)?.toInt() ?? 0),
            expiryDate: DateTime.tryParse(line['expiry_date'] as String? ?? ''),
          ),
    ];
    final snapshot = ReceiveDraftSnapshot(
      supplierId: (json['supplier_id'] as num?)?.toInt(),
      supplierRef: json['supplier_ref'] as String?,
      lines: lines,
    );
    return snapshot.isEmpty ? null : snapshot;
  }
}

class _ReceiveStockSheetState extends State<ReceiveStockSheet> {
  /// The lines, in the order they were added.
  final List<_ReceiptLine> _lines = <_ReceiptLine>[];

  /// The suppliers on the picker. Starts as the caller's list and grows when
  /// a supplier is added from here — the caller reloads the list after the
  /// sheet closes, and until then the new supplier must stay selectable.
  late List<Supplier> _suppliers = List.of(widget.suppliers);

  int? _supplierId;
  final TextEditingController _supplierRef = TextEditingController();
  final TextEditingController _supplierPin = TextEditingController();
  final TextEditingController _etimsInvoiceRef = TextEditingController();
  final TextEditingController _inputVat = TextEditingController();
  String _taxEvidenceStatus = 'needs_review';

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ReceiveDraftSnapshot? draft = widget.draft;
    if (draft != null) {
      _supplierId = draft.supplierId;
      _supplierRef.text = draft.supplierRef ?? '';
      for (final StockReceiptLine line in draft.lines) {
        _lines.add(_ReceiptLine(
          productId: line.productId,
          productName: line.productName,
          qty: line.qty,
          unitCost: line.unitCost,
          tracksExpiry: widget.products
              .firstWhere((p) => p.id == line.productId,
                  orElse: () => Product(
                        id: line.productId,
                        name: line.productName,
                        category: '',
                        costPrice: Money.zero,
                        sellPrice: Money.zero,
                        stockQty: 0,
                        reorderLevel: 0,
                        updatedAt: '',
                      ))
              .trackExpiry,
          expiryDate: line.expiryDate,
        ));
      }
    }
  }

  @override
  void dispose() {
    _supplierRef.dispose();
    _supplierPin.dispose();
    _etimsInvoiceRef.dispose();
    _inputVat.dispose();
    super.dispose();
  }

  int get _totalMinor => _lines.fold<int>(
        0,
        (int sum, _ReceiptLine line) => sum + line.lineCostMinor,
      );

  /// Autosaves the session, so a killed app loses nothing. Cheap (a single
  /// JSON row), and every change lands it — not just on post.
  ///
  /// The write FAILS SOFT: a store that will not open (a till's storage mid-
  /// boot, or a surface running without one) owes nobody a draft, and the
  /// delivery itself is unaffected — the loss it risks is one session, and
  /// only when the store is already gone.
  Future<void> _autosave() async {
    try {
      await _autosaveNow();
    } catch (_) {
      // Benign: the draft is a convenience, and the store said no.
    }
  }

  Future<void> _autosaveNow() async {
    if (_lines.isEmpty && _supplierId == null && _supplierRef.text.isEmpty) {
      await DatabaseHelper.instance.saveReceiveDraft(widget.staffId, null);
      return;
    }
    await DatabaseHelper.instance
        .saveReceiveDraft(widget.staffId, <String, Object?>{
      'supplier_id': _supplierId,
      'supplier_ref': _supplierRef.text,
      'lines': <Map<String, Object?>>[
        for (final _ReceiptLine line in _lines)
          <String, Object?>{
            'product_id': line.productId,
            'product_name': line.productName,
            'qty': line.qty,
            'unit_cost_minor': line.unitCost.minorUnits,
            'expiry_date': line.expiryDate?.toIso8601String(),
          },
      ],
    });
  }

  /// Throws a resumed draft away. Deliberate, irreversible in feel, and a
  /// decision the person makes once — the shared confirm dialog.
  ///
  /// The SHEET closes before the draft's row is cleared: the answer they
  /// gave is already made — it belongs to the screen, not the storage. A
  /// clear that lags or fails leaves the draft standing, which is harmless:
  /// a draft is offered again, not restored over anything.
  Future<void> _discardDraft() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ConfirmOutcome outcome = await confirmIrreversible(
      context,
      title: l10n.receiveDraftDiscardTitle,
      message: l10n.receiveDraftDiscardMessage,
      confirmLabel: l10n.receiveDraftDiscardConfirm,
    );
    if (outcome is! ConfirmAccepted) return;
    if (!mounted) return;
    Navigator.of(context).pop(0); // A dismissed-not-posted resume.
    await DatabaseHelper.instance.saveReceiveDraft(widget.staffId, null);
  }

  /// The number of lines a product already has, so a repeat entry knows.
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
        tracksExpiry: product.trackExpiry,
      ));
    });
    await _autosave();
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
              expiryDate: line.expiryDate,
            ),
        ],
        supplierId: _supplierId,
        supplierRef:
            _supplierRef.text.trim().isEmpty ? null : _supplierRef.text.trim(),
        supplierPin:
            _supplierPin.text.trim().isEmpty ? null : _supplierPin.text.trim(),
        etimsInvoiceRef: _etimsInvoiceRef.text.trim().isEmpty
            ? null
            : _etimsInvoiceRef.text.trim(),
        inputVatMinor: int.tryParse(_inputVat.text.trim()),
        taxEvidenceStatus: _taxEvidenceStatus,
        staffName: widget.staffName,
        staffId: widget.staffId,
        costingMode: widget.costingMode,
      );
      // The draft is done for: the delivery is in the history.
      if (!mounted) return;
      await DatabaseHelper.instance.saveReceiveDraft(widget.staffId, null);
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
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(l10n.receiveTitle, style: type.titleLarge),
                    ),
                    if (widget.draft != null)
                      TextButton(
                        onPressed: _discardDraft,
                        child: Text(l10n.receiveDraftDiscardAction),
                      ),
                  ],
                ),
              ),
              SizedBox(height: spacing.xs),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: Text(
                  widget.draft != null
                      ? l10n.receiveDraftRestored
                      : l10n.receiveSubtitle,
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            initialValue: _supplierId,
                            isExpanded: true,
                            items: <DropdownMenuItem<int?>>[
                              DropdownMenuItem<int?>(
                                value: null,
                                child: Text(l10n.receiveNoSupplier),
                              ),
                              for (final Supplier supplier in _suppliers)
                                if (supplier.id != null)
                                  DropdownMenuItem<int?>(
                                    value: supplier.id,
                                    child: Text(supplier.name),
                                  ),
                            ],
                            onChanged: (int? value) {
                              setState(() => _supplierId = value);
                              _autosave();
                            },
                          ),
                        ),
                        SizedBox(width: spacing.sm),
                        // A supplier the shop has not written down yet is
                        // added HERE, name and number together: the person
                        // knows who brought the delivery while the delivery
                        // is on the counter — and asking for their number
                        // NOW is what lets the app order from them later.
                        IconButton.filledTonal(
                          onPressed: _addSupplier,
                          tooltip: l10n.receiveAddSupplierAction,
                          icon: const Icon(Icons.person_add_alt_1),
                        ),
                      ],
                    ),
                    SizedBox(height: spacing.sm),
                    TextField(
                      controller: _supplierRef,
                      decoration: InputDecoration(
                        labelText: l10n.receiveSupplierRefLabel,
                        hintText: l10n.receiveSupplierRefHint,
                      ),
                      onChanged: (String value) {
                        _autosave();
                      },
                    ),
                    SizedBox(height: spacing.sm),
                    TextField(
                      controller: _supplierPin,
                      decoration: const InputDecoration(
                        labelText: 'Supplier PIN (optional)',
                      ),
                      onChanged: (_) => _autosave(),
                    ),
                    SizedBox(height: spacing.sm),
                    TextField(
                      controller: _etimsInvoiceRef,
                      decoration: const InputDecoration(
                        labelText: 'eTIMS/TIMS invoice reference (optional)',
                      ),
                      onChanged: (_) => _autosave(),
                    ),
                    SizedBox(height: spacing.sm),
                    TextField(
                      controller: _inputVat,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Input VAT in cents (optional)',
                        helperText:
                            'Leave blank until the invoice is verified.',
                      ),
                      onChanged: (_) => _autosave(),
                    ),
                    SizedBox(height: spacing.sm),
                    DropdownButtonFormField<String>(
                      initialValue: _taxEvidenceStatus,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Tax evidence status',
                      ),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem(
                          value: 'needs_review',
                          child: Text('Needs review'),
                        ),
                        DropdownMenuItem(
                          value: 'verified',
                          child: Text('Verified'),
                        ),
                        DropdownMenuItem(
                          value: 'valid_exception',
                          child: Text('Valid exception'),
                        ),
                        DropdownMenuItem(
                          value: 'unmatched',
                          child: Text('Unmatched'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _taxEvidenceStatus = value);
                        _autosave();
                      },
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
                        onChanged: (_ReceiptLine line) {
                          setState(() => _lines[i] = line);
                          _autosave();
                        },
                        onRemoved: () {
                          setState(() => _lines.removeAt(i));
                          _autosave();
                        },
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
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                      final bool stack = constraints.maxWidth < 360 ||
                          MediaQuery.textScalerOf(context).scale(1) > 1.3;
                      final Widget total = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(l10n.receiveTotalLabel, style: type.bodyMedium),
                          Text(
                            formatMoney(Money.fromMinor(_totalMinor)),
                            style: type.titleLarge,
                          ),
                        ],
                      );
                      final Widget postButton = FilledButton(
                        onPressed: _saving ? null : _post,
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(l10n.receivePostAction),
                      );
                      if (stack) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            total,
                            SizedBox(height: spacing.sm),
                            postButton,
                          ],
                        );
                      }
                      return Row(
                        children: <Widget>[
                          Expanded(child: total),
                          postButton,
                        ],
                      );
                    },
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
    if (!mounted) return;
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

  /// Adds a supplier without leaving the delivery: name, and the number the
  /// app will order from later.
  Future<void> _addSupplier() async {
    if (!mounted) return;
    final Supplier? added = await showModalBottomSheet<Supplier>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _AddSupplierSheet(
        knownNames: <String>{
          for (final Supplier supplier in _suppliers)
            supplier.name.toLowerCase(),
        },
      ),
    );
    if (added == null) return;
    setState(() {
      _suppliers = List.of(_suppliers)..add(added);
      _supplierId = added.id;
    });
    await _autosave();
  }
}

/// Adds a supplier: a name and the number the restock reminder will reach.
///
/// Opened from the delivery header, so the shop can buy from a new person
/// without walking away from the counter. The PHONE is validated as a Kenyan
/// number before it is saved, because a number saved broken is worse than no
/// number: it looks receivable until the day an order must actually reach it.
class _AddSupplierSheet extends StatefulWidget {
  const _AddSupplierSheet({required this.knownNames});

  /// Lower-case names already on the list, so a duplicate is caught before
  /// it is saved — the database would refuse it anyway, but reading it early
  /// puts the message next to the field rather than next to the button.
  final Set<String> knownNames;

  @override
  State<_AddSupplierSheet> createState() => _AddSupplierSheetState();
}

class _AddSupplierSheetState extends State<_AddSupplierSheet> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final int id = await DatabaseHelper.instance.addSupplier(
        name: _name.text,
        phone: _phone.text,
      );
      final Supplier supplier = await DatabaseHelper.instance
          .getSuppliers()
          .then((List<Supplier> all) =>
              all.firstWhere((Supplier s) => s.id == id));
      if (!mounted) return;
      Navigator.of(context).pop(supplier);
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.supplierSaveFailed(error.message.toString());
      });
    } on ArgumentError catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.supplierSaveFailed(error.message?.toString() ?? '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(spacing.lg, spacing.lg, spacing.lg,
            spacing.lg + MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(l10n.supplierAddTitle, style: type.titleLarge),
              SizedBox(height: spacing.xs),
              Text(
                l10n.supplierAddSubtitle,
                style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
              ),
              SizedBox(height: spacing.md),
              TextFormField(
                controller: _name,
                autofillHints: const <String>[AutofillHints.name],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.supplierNameLabel,
                ),
                validator: (String? value) {
                  final String trimmed = (value ?? '').trim();
                  if (trimmed.isEmpty) {
                    return l10n.supplierNameTooShort;
                  }
                  if (widget.knownNames.contains(trimmed.toLowerCase())) {
                    return l10n.supplierNameAlreadyOnList;
                  }
                  return null;
                },
              ),
              SizedBox(height: spacing.sm),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const <String>[AutofillHints.telephoneNumber],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (String _) => _save(),
                decoration: InputDecoration(
                  labelText: l10n.supplierPhoneLabel,
                  helperText: l10n.supplierPhoneHelper,
                  prefixText: '+254 ',
                ),
                validator: (String? value) {
                  final String? typed = value?.trim();
                  if (typed == null || typed.isEmpty) return null; // optional
                  final String? canonical = normaliseKenyanPhone(typed) ??
                      normaliseKenyanPhone('254$typed');
                  if (canonical == null) {
                    return l10n.supplierPhoneInvalid;
                  }
                  return null;
                },
              ),
              if (_error != null) ...<Widget>[
                SizedBox(height: spacing.sm),
                PersistentBanner(
                  tone: StatusTone.danger,
                  icon: Icons.cancel_outlined,
                  message: _error!,
                ),
              ],
              SizedBox(height: spacing.md),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.supplierSaveAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of the delivery, as the person is filling it in.
class _ReceiptLine {
  _ReceiptLine({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.unitCost,
    this.tracksExpiry = false,
    this.expiryDate,
  });

  final int productId;
  final String productName;
  final double qty;
  final Money unitCost;
  final bool tracksExpiry;
  final DateTime? expiryDate;

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
                      tracksExpiry: line.tracksExpiry,
                      expiryDate: line.expiryDate,
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
                      tracksExpiry: line.tracksExpiry,
                      expiryDate: line.expiryDate,
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
          if (line.tracksExpiry)
            TextButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                  initialDate: line.expiryDate ??
                      DateTime.now().add(const Duration(days: 30)),
                );
                if (picked == null) return;
                onChanged(_ReceiptLine(
                  productId: line.productId,
                  productName: line.productName,
                  qty: line.qty,
                  unitCost: line.unitCost,
                  tracksExpiry: line.tracksExpiry,
                  expiryDate: picked,
                ));
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(line.expiryDate == null
                  ? 'Add expiry date'
                  : 'Expires ${line.expiryDate!.year}-${line.expiryDate!.month.toString().padLeft(2, '0')}-${line.expiryDate!.day.toString().padLeft(2, '0')}'),
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
