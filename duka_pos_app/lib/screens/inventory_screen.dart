import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../db/database_helper.dart';
import '../services/barcode/barcode_service.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/backend_service.dart';
import '../utils/money.dart';
import '../utils/units.dart';
import '../widgets/variant_catalogue.dart';
import '../widgets/variant_form_sheet.dart';
import 'home_shell.dart';
import 'shot_cups_screen.dart';
import '../theme/app_theme.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Product> _products = [];

  /// Which products are sold as variants, and what those variants are.
  ///
  /// Loaded with the products rather than per row: the list needs to know for
  /// every tile whether it has variants to offer, and a query per tile is a
  /// list that stutters on exactly the shops with the most stock.
  VariantCatalogue _variants = VariantCatalogue.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _products = []);
    final p = await DatabaseHelper.instance.getProducts();
    final catalogue = await VariantCatalogue.load();
    if (mounted) {
      setState(() {
        _products = p;
        _variants = catalogue;
      });
    }
  }

  Future<void> _openEditor([Product? existing]) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductEditor(existing: existing, onSaved: _load),
    );
  }

  Future<void> _adjustStock(Product p) async {
    // A product sold as variants has no stock count of its own to correct: its
    // `stock_qty` is the sum of its variants (see
    // VariantCatalogue.writeAggregateStock), so adjusting the parent would
    // overwrite that sum with a number nothing derives from. Correct one
    // variant instead, chosen by name.
    if (_variants.sellsAsVariants(p)) {
      await _adjustVariantStock(p);
      return;
    }
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _AdjustDialog(product: p),
    );
    if (result == null) return;
    final delta = int.tryParse(result['delta'] ?? '');
    if (delta == null || delta == 0) return;
    if (!mounted) return;
    final state = context.read<AppState>();
    final staffName = state.currentStaffName!;
    // Shrinkage is reviewed per cashier, and `deleteStaffWithTombstone`
    // anonymises the ledger by `staff_id`. Recording only the display name
    // leaves the removed cashier named on every adjustment they made.
    int? staffId;
    String? staffRemoteId;
    if (!state.isOwnerSession) {
      final staff = await DatabaseHelper.instance.getStaff();
      final match = staff.where((s) => s.name == staffName);
      staffId = match.isEmpty ? null : match.first.id;
      staffRemoteId = match.isEmpty ? null : match.first.remoteId;
    }
    try {
      await DatabaseHelper.instance.adjustStock(
          StockAdjustment(
            productId: p.id!,
            productName: p.name,
            delta: delta,
            reason: result['reason'] ?? '',
            staffName: staffName,
            createdAt: DateTime.now().toIso8601String(),
          ),
          staffId: staffId);
      await _load();
      // The server owns the authoritative stock count, so the correction has to
      // be pushed as an adjustment rather than folded into the next catalogue
      // sync. Reported, not silent: the local count is already correct, but the
      // shop's other devices will not see this change until it lands.
      if (mounted) {
        final pushed = await BackendService.adjustStockOnBackend(
          product: p,
          delta: delta,
          reason: result['reason'],
          staffProfileId: staffRemoteId,
        );
        if (!pushed && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Stock updated on this till. The online count will catch up on the next sync.')));
        }
      }
    } on StateError catch (error) {
      if (mounted) {
        final message = error.toString().contains('below zero')
            ? 'Stock cannot go below zero. Check the current quantity and try again.'
            : 'Stock update failed. Refresh the inventory and try again.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Couldn’t adjust stock. Try again.')));
      }
    }
  }

  /// Corrects the stock of one variant of a product sold as variants.
  ///
  /// Deliberately not pushed to the backend: the adjustment API takes a product
  /// and adjusts *that* product's count, and this count belongs to a variant.
  /// Pushing it as a product adjustment would move the server's aggregate by a
  /// number that means something different there, so the correction stays on
  /// this till and arrives with the variants themselves once the backend carries
  /// them.
  Future<void> _adjustVariantStock(Product p) async {
    final variants = _variants.of(p);
    if (variants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('Add ${p.name}\'s variants first — its stock is their total.'),
      ));
      return;
    }
    final chosen = await showDialog<ProductVariant>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Which variant? · ${p.name}'),
        children: [
          for (final variant in variants)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, variant),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  variant.isLow
                      ? Icons.warning_amber_outlined
                      : Icons.label_outline,
                ),
                title: Text(variant.name),
                subtitle: Text('${variant.stockQty} in stock'),
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _AdjustDialog(product: p, variant: chosen),
    );
    if (result == null) return;
    final delta = int.tryParse(result['delta'] ?? '');
    if (delta == null || delta == 0) return;
    try {
      await VariantCatalogue.adjustVariantStock(chosen.id!, delta.toDouble());
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('${chosen.label} is now ${chosen.stockQty + delta} in stock.'),
      ));
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().contains('below zero')
            ? 'Stock cannot go below zero. Check the current quantity and try again.'
            : 'Stock update failed. Refresh the inventory and try again.'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn’t adjust stock. Try again.')));
    }
  }

  Future<void> _delete(Product p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove ${p.name} from inventory?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper.instance.deactivateProduct(p.id!);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = context.watch<AppState>().isOwnerSession;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: 'Add product',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          itemCount: _products.length + 1,
          itemBuilder: (_, i) {
            // Row zero is the shot-cup entry rather than a product: it is a way of selling
            // what is already in the catalogue, not another line of it, and
            // burying it under the first hundred sodas is how a bar never finds
            // the feature that makes it a bar.
            if (i == 0) {
              return Semantics(
                label:
                    'Shot cups. Fixed-size shots of any drink in your inventory.',
                child: ListTile(
                  leading: const Icon(Icons.local_drink_outlined),
                  title: const Text('Shot cups'),
                  subtitle: const Text(
                      'Sell fixed-size shots of any drink in your inventory'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => const ShotCupsScreen()),
                  ),
                ),
              );
            }
            final p = _products[i - 1];
            final variantCount = _variants.of(p).length;
            return Semantics(
              label:
                  '${p.name}, ${formatMoney(p.sellPrice)}, ${p.stockQty} in stock',
              child: ListTile(
                title: Text(p.name),
                subtitle: Text([
                  p.category,
                  formatMoney(p.sellPrice),
                  'margin ${p.marginPct.toStringAsFixed(0)}%',
                  // "Sold as variants" is the difference between one row and
                  // four at the till, so it is stated on the list rather than
                  // left to be discovered when a cashier cannot find Dark.
                  if (_variants.tracks(p)) 'no variants yet',
                  if (variantCount > 0)
                    '$variantCount variant${variantCount == 1 ? '' : 's'}',
                ].join(' · ')),
                leading: CircleAvatar(
                  backgroundColor:
                      p.isLow ? DukaColors.surfaceWarm : DukaColors.surface,
                  child: Text('${p.stockQty}',
                      style: TextStyle(
                          fontSize: 12,
                          color: p.isLow
                              ? DukaColors.danger
                              : DukaColors.success)),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') _openEditor(p);
                    if (v == 'adjust') _adjustStock(p);
                    if (v == 'delete') _delete(p);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(
                        value: 'adjust', child: Text('Adjust stock')),
                    if (isOwner)
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProductEditor extends StatefulWidget {
  final Product? existing;
  final VoidCallback onSaved;
  const _ProductEditor({this.existing, required this.onSaved});
  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  late final TextEditingController _name,
      _category,
      _cost,
      _price,
      _stock,
      _reorder,
      _stamp,
      _bottleMl,
      _halfPrice,
      _quarterPrice,
      _barcode;
  String? _error;

  /// Codes already attached to this product, at both levels.
  ///
  /// A list rather than one field, because a product routinely answers to more
  /// than one: the supplier's EAN, a second distributor's, a code the owner
  /// assigned, and a code per variant. Barcodes are written through the barcode
  /// API rather than `upsertProduct`, which rewrites the whole product row and
  /// would erase them on the next unrelated save.
  ///
  /// Each row carries the level it resolves at, because a code on the product
  /// and a code on one of its variants behave differently at the till and the
  /// owner has to be able to tell which is which.
  List<ProductCode> _codes = [];

  /// Variants being edited in this dialog session, staged rather than written.
  ///
  /// `product_variants.product_id` is NOT NULL, so a variant cannot be saved
  /// before the product row exists — and a variant the owner has typed but not
  /// finished should not be in the catalogue at all if they then back out.
  List<VariantDraft> _drafts = [];

  /// Variants already in the table that this session removes. Applied after the
  /// product save, so backing out of the sheet undoes the removal too.
  final List<int> _removedVariantIds = [];

  /// Whether the product is sold as variants. Read from the row rather than
  /// from the passed-in [Product], because `Product.fromMap` does not populate
  /// it — a product that *is* sold as variants arrives here looking like one
  /// that is not, and saving it would quietly turn the feature off.
  bool _trackVariants = false;

  /// What the product is measured in, for the same reason as [_trackVariants].
  ProductUnit _unit = ProductUnit.each;

  /// Covers the codes, the variants and the two flag columns, which arrive in
  /// three separate reads.
  bool _loadingMeta = true;

  /// Volume sizes this shop has used before, most-used first.
  ///
  /// Offered as one-tap chips under the keg/tank size field. A bar selling
  /// Tusker, a keg of.proto and a 50-litre tank types three different five-digit
  /// numbers that are all the same shop remembering its own stock, and the chips
  /// turn three remembered numbers into one remembered list.
  ///
  /// Read shop-wide rather than per product: a keg size is not a property of one
  /// product, and the product being typed may not have a row yet.
  List<CupSizeSuggestion> _sizeSuggestions = const [];

  /// How many chips to offer before the row stops being scannable.
  static const _maxSizeSuggestions = 6;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _cost.dispose();
    _price.dispose();
    _stock.dispose();
    _reorder.dispose();
    _stamp.dispose();
    _bottleMl.dispose();
    _halfPrice.dispose();
    _quarterPrice.dispose();
    _barcode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _category = TextEditingController(text: e?.category ?? '');
    // Seeded through an explicit formatter, never `toString()`.
    //
    // `Money.toString()` returns `Money(50000 minor units)` — the debug
    // representation, in cents. Putting that in a field and then parsing it
    // back failed, so every price was both unreadable and unsaveable, and an
    // optional price read as "unparseable" was silently written back as NULL.
    // A helper here means the correct conversion cannot be forgotten in one
    // field out of seven.
    _cost = TextEditingController(text: _editAmount(e?.costPrice));
    _price = TextEditingController(text: _editAmount(e?.sellPrice));
    _stock = TextEditingController(text: _editQuantity(e?.stockQty));
    _reorder = TextEditingController(text: e?.reorderLevel.toString() ?? '5');
    _stamp = TextEditingController(text: e?.exciseStampBatch ?? '');
    _bottleMl = TextEditingController(text: e?.bottleMl.toString() ?? '750');
    _halfPrice = TextEditingController(text: _editAmount(e?.halfPrice));
    _quarterPrice = TextEditingController(text: _editAmount(e?.quarterPrice));
    _barcode = TextEditingController();
    _loadMeta();
    _loadSizeSuggestions();
  }

  Future<void> _loadSizeSuggestions() async {
    final loaded = await DatabaseHelper.instance.getCupSizeSuggestions();
    if (!mounted) return;
    setState(() => _sizeSuggestions = loaded);
  }

  /// The chips worth offering under the size field.
  ///
  /// Hidden for a countable product: "750 ml" next to a thing with no size is
  /// a question nobody asked, and a countable product's field is a legacy
  /// leftover that is ignored on save.
  List<CupSizeSuggestion> get _visibleSizeSuggestions =>
      _unit == ProductUnit.each ? const [] : _sizeSuggestions;

  Widget _sizeSuggestionChips() => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Semantics(
          container: true,
          label: 'Sizes you have used before',
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in _visibleSizeSuggestions.take(_maxSizeSuggestions))
                ActionChip(
                  label: Text(Volume(s.sizeMl.toDouble()).display),
                  onPressed: () => _bottleMl.text = s.sizeMl.toString(),
                ),
            ],
          ),
        ),
      );

  /// Reads everything about an existing product that the product row alone
  /// cannot tell us: its variants, its codes at both levels, and the two
  /// columns `Product.fromMap` leaves at their defaults.
  Future<void> _loadMeta() async {
    final existing = widget.existing;
    if (existing?.id == null) {
      if (mounted) setState(() => _loadingMeta = false);
      return;
    }
    final productId = existing!.id!;
    final db = DatabaseHelper.instance;
    final flags = await VariantCatalogue.productFlags(productId);
    final variants = await db.getVariants(productId, activeOnly: false);
    final codes = await VariantCatalogue.codesForProduct(productId);
    if (!mounted) return;
    String storedCodeFor(int? variantId) => codes
        .firstWhere(
          (code) => code.variantId == variantId,
          orElse: () => const ProductCode(barcode: ''),
        )
        .barcode;
    setState(() {
      _unit = flags.unit;
      // Variants that exist are treated as "sold as variants" even when the flag
      // was never set: turning the flag off here would hide variants the owner
      // can see, and would leave them unsellable at the till.
      _trackVariants = flags.trackVariants || variants.isNotEmpty;
      _drafts = [
        for (final variant in variants)
          VariantDraft.fromVariant(variant,
              storedBarcode: storedCodeFor(variant.id)),
      ];
      _codes = codes;
      _loadingMeta = false;
    });
  }

  /// Turns "sold as variants" on or off.
  ///
  /// On: the stock field becomes the variants' total (kept in sync on save), and
  /// the variant list appears. Off: the stock field goes back to being this
  /// product's own count. Any variants already added stay where they are — they
  /// are the owner's data, and hiding them would look like losing them.
  void _setTrackVariants(bool value) {
    setState(() {
      _trackVariants = value;
      if (value && _stock.text.trim().isEmpty) {
        final total = _drafts.fold<double>(0, (sum, d) => sum + d.stockQty);
        _stock.text = _editQuantity(total);
      }
    });
  }

  /// A money value as editable whole shillings, or empty when absent.
  ///
  /// Whole shillings rather than two decimals because that is what these fields
  /// have always accepted and what a Kenyan shopkeeper types. The internal
  /// representation stays integer cents; this is purely the display edge.
  static String _editAmount(Money? value) {
    if (value == null) return '';
    final major = value.minorUnits ~/ kMinorUnitsPerMajor;
    final cents = value.minorUnits % kMinorUnitsPerMajor;
    // Show cents only when they exist, so a whole-shilling price does not read
    // as "500.00" while the shop's price list says "500".
    return cents == 0 ? '$major' : '$major.${cents.toString().padLeft(2, '0')}';
  }

  /// A stock quantity for editing: no trailing `.0` for a whole number.
  static String _editQuantity(double? value) {
    if (value == null) return '';
    return value % 1 == 0 ? value.toInt().toString() : value.toString();
  }

  Future<void> _reloadCodes() async {
    final existing = widget.existing;
    if (existing?.id == null) return;
    final codes = await VariantCatalogue.codesForProduct(existing!.id!);
    if (!mounted) return;
    setState(() => _codes = codes);
  }

  Future<void> _addBarcode() async {
    final raw = _barcode.text.trim();
    final code = Barcode.normalise(raw);
    final problem = Barcode.rejectionReason(code);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    // The product has to exist before a barcode can point at it, so an
    // unsaved new product gets its codes after the save rather than before.
    final existing = widget.existing;
    if (existing?.id == null) {
      setState(
          () => _error = 'Save the product first, then add its barcode(s).');
      return;
    }
    final added = await DatabaseHelper.instance.addBarcode(
      productId: existing!.id!,
      barcode: code,
      kind: BarcodeKind.supplier,
    );
    if (!mounted) return;
    if (!added) {
      // `barcode TEXT PRIMARY KEY` makes the duplicate impossible rather than
      // merely discouraged, so this is the one place a duplicate can surface —
      // and it names the product that already owns the code, which tells the
      // owner which product to remove it from.
      final owner = await DatabaseHelper.instance.getProductOwningBarcode(code);
      if (!mounted) return;
      setState(() => _error = owner == null
          ? 'That barcode is already on another product.'
          : 'That barcode is already on ${owner.name}.');
      return;
    }
    _barcode.clear();
    setState(() => _error = null);
    await _reloadCodes();
  }

  Future<void> _removeBarcode(ProductCode code) async {
    await DatabaseHelper.instance.removeBarcode(code.barcode);
    if (!mounted) return;
    setState(() => _error = null);
    await _reloadCodes();
  }

  /// Changes what a code is labelled as. Informational only, but a distributor
  /// code labelled "own" is the kind of thing that makes an import's duplicate
  /// report unreadable three months later.
  Future<void> _cycleBarcodeKind(ProductCode code) async {
    final index = BarcodeKind.kinds.indexOf(code.kind);
    final next = BarcodeKind.kinds[(index + 1) % BarcodeKind.kinds.length];
    await DatabaseHelper.instance.setBarcodeKind(code.barcode, next);
    if (!mounted) return;
    await _reloadCodes();
  }

  // ---------------- Variants ----------------

  /// The parent as the form currently has it, for seeding a new variant.
  ///
  /// Read from the *fields* rather than from the stored product, so a variant
  /// added after the owner has just corrected the price inherits the price they
  /// are looking at. Every field falls back to the stored value rather than
  /// failing, because seeding is a convenience and must never be the reason a
  /// variant cannot be added.
  Product _draftParent() {
    final existing = widget.existing;
    double number(String text, double fallback) =>
        double.tryParse(text.trim()) ?? fallback;
    return Product(
      id: existing?.id,
      name: _name.text.trim().isEmpty
          ? (existing?.name ?? 'This product')
          : _name.text.trim(),
      category:
          _category.text.trim().isEmpty ? 'General' : _category.text.trim(),
      costPrice:
          Money.fromMajor(number(_cost.text, existing?.costPrice.asMajor ?? 0)),
      sellPrice: Money.fromMajor(
          number(_price.text, existing?.sellPrice.asMajor ?? 0)),
      stockQty: number(_stock.text, existing?.stockQty ?? 0),
      reorderLevel:
          int.tryParse(_reorder.text.trim()) ?? existing?.reorderLevel ?? 0,
      bottleMl:
          int.tryParse(_bottleMl.text.trim()) ?? existing?.bottleMl ?? 750,
      unit: _unit,
      trackVariants: _trackVariants,
      active: existing?.active ?? true,
      updatedAt: DateTime.now().toIso8601String(),
      remoteId: existing?.remoteId,
    );
  }

  Future<void> _addVariant() async {
    final draft = await showVariantFormSheet(
      context,
      seed: VariantDraft.seededFrom(
        parent: _draftParent(),
        parentUnit: _unit,
        position: _drafts.length,
      ),
      // Null while the product itself is still an unsaved draft, in which case
      // the sheet offers the shop-wide cup sizes instead of this product's.
      parentProductId: widget.existing?.id,
    );
    if (draft == null || !mounted) return;
    setState(() => _drafts.add(draft));
  }

  Future<void> _editVariant(int index) async {
    final existingDraft = _drafts[index];
    final draft = await showVariantFormSheet(
      context,
      seed: existingDraft,
      title: 'Edit ${existingDraft.name}',
      parentProductId: widget.existing?.id,
    );
    if (draft == null || !mounted) return;
    setState(() => _drafts[index] = draft);
  }

  /// Stages a variant's removal, after asking.
  ///
  /// Asked, always, even for a variant that has never been written: a variant
  /// holding the only barcode a supplier's label carries, removed by a
  /// mis-tap, stops that label resolving at the till with nothing on screen to
  /// say why.
  Future<void> _removeVariant(int index) async {
    final draft = _drafts[index];
    if (!draft.isNew) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Remove ${draft.name}?'),
          content: Text(draft.hasStoredBarcode
              ? 'Its barcode is freed so another variant can use it. Sales already recorded keep the name they were sold under.'
              : 'It stops being offered at the till. Sales already recorded keep the name they were sold under.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    setState(() {
      if (draft.id != null) {
        _removedVariantIds.add(draft.id!);
        // The code goes with the variant, so the list must stop showing it
        // before the save that actually frees it.
        _codes = _codes.where((code) => code.variantId != draft.id).toList();
      }
      _drafts.removeAt(index);
      for (var i = 0; i < _drafts.length; i++) {
        _drafts[i] = _drafts[i].copyWith(position: i);
      }
    });
  }

  /// One row in the variant list.
  ///
  /// Shows the four things that tell two variants apart: what it is called, how
  /// big it is, what it costs and how many are left. Swipe removes it, the menu
  /// does the same thing for anyone who cannot swipe, and both go through the
  /// same confirmation.
  Widget _variantRow(int index) {
    final draft = _drafts[index];
    final low = draft.stockQty <= draft.reorderLevel;
    return Dismissible(
      // Keyed by identity, not by position: a `ValueKey` on the index would
      // make a removed row animate out of the wrong place once the list closes
      // the gap.
      key: ValueKey(
          'variant-${draft.id ?? 'new-${draft.name}-${draft.position}'}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Icon(Icons.delete_outline),
      ),
      // The row is removed by the callback above, not by the dismiss itself, so
      // returning false keeps `Dismissible` from also trying to remove a widget
      // that is no longer in the list.
      confirmDismiss: (_) async {
        await _removeVariant(index);
        return false;
      },
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: low ? DukaColors.surfaceWarm : DukaColors.surface,
          child: Text('${draft.stockQty}',
              style: TextStyle(
                  fontSize: 12,
                  color: low ? DukaColors.danger : DukaColors.success)),
        ),
        title: Text(draft.name.trim().isEmpty ? 'New variant' : draft.name),
        subtitle: Text([
          // Blank for a countable variant: it has no size, and printing "0 ml"
          // would invent one.
          if (draft.sizeLabel.isNotEmpty) draft.sizeLabel,
          formatMoney(draft.sellPrice),
          low ? 'low stock' : '${editVariantQuantity(draft.stockQty)} in stock',
        ].join(' · ')),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') _editVariant(index);
            if (value == 'remove') _removeVariant(index);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
        onTap: () => _editVariant(index),
      ),
    );
  }

  /// Writes the staged variants, in the same dialog session as the product.
  ///
  /// Removals first, so a barcode freed by a removed variant can be taken by one
  /// added in the same save, and so the aggregate is computed from what is
  /// actually left. Barcodes are written after their variant exists, because the
  /// code points at the variant's row.
  Future<void> _saveVariants(int productId) async {
    final db = DatabaseHelper.instance;
    for (final removedId in _removedVariantIds) {
      // Also frees that variant's barcodes.
      await db.deleteVariant(removedId);
    }
    for (var i = 0; i < _drafts.length; i++) {
      final draft = _drafts[i];
      // Position follows the order on screen, so reordering is reordering and
      // the till offers Dark before Regular because the owner put it there.
      final variantId = await db
          .upsertVariant(draft.copyWith(position: i).toVariant(productId));
      final code = draft.barcode.trim();
      if (draft.hasStoredBarcode && draft.barcodeChanged) {
        await db.removeBarcode(draft.storedBarcode);
      }
      // Only write a code when there is a new one to write: an unchanged code is
      // already in the table, and re-inserting it would fail as a duplicate of
      // itself and take the whole save down with it.
      if (code.isNotEmpty && (draft.isNew || draft.barcodeChanged)) {
        final added = await VariantCatalogue.addVariantCode(
          productId: productId,
          variantId: variantId,
          barcode: code,
        );
        if (!added) {
          // Same constraint as a product-level code: one code resolves to
          // exactly one thing, so a clash is reported rather than resolved.
          final owner = await db.getProductOwningBarcode(code);
          throw StateError(owner == null
              ? 'Barcode $code is already used by another product or variant.'
              : 'Barcode $code is already on ${owner.name}.');
        }
      }
    }
    if (_trackVariants) {
      // A product sold as variants has no stock count of its own; the parent's
      // row carries the total the ledger checks.
      await VariantCatalogue.writeAggregateStock(productId);
    }
  }

  /// Remembers the size the owner just used, so the chips above the field
  /// improve the next time they are opened.
  ///
  /// Recorded shop-wide rather than against this product: a keg size is a fact
  /// about the shop's bottles, not about one line of the catalogue, and a shop
  /// that pours the same tank behind two different drinks should see the size
  /// offered for both.
  ///
  /// Failures here are swallowed deliberately. The size is already written to
  /// the product row, which is what the till sells; losing a suggestion is not
  /// worth failing a save the owner can see succeed.
  Future<void> _rememberSize(int sizeMl) async {
    if (sizeMl <= 0) return;
    try {
      await DatabaseHelper.instance.upsertCupSizeSuggestion(sizeMl: sizeMl);
    } catch (_) {
      // Intentionally ignored — see above.
    }
  }

  /// Reads an optional price field.
  ///
  /// The distinction that matters here is **empty** versus **unparseable**, and
  /// conflating them is how prices silently disappeared.
  ///
  /// `double.tryParse` returns null for both. Treating a non-numeric entry as
  /// "not set" meant that a field which failed to parse — which happened to
  /// every existing product, because the field was seeded with `Money.toString()`
  /// — was written back as NULL. Merely opening a product and saving an
  /// unrelated field therefore erased its half and quarter prices, with no
  /// error anywhere. An unparseable value is now an error the owner can see; only
  /// a genuinely empty field means "this product is not sold in portions".
  Money? _optionalPrice(TextEditingController controller, String label) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null) {
      throw FormatException(
          '$label must be a number, or empty if not sold in portions');
    }
    if (!Money.isValidMajor(parsed)) {
      throw FormatException('$label must be 0 or more');
    }
    return Money.fromMajor(parsed);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final category =
        _category.text.trim().isEmpty ? 'General' : _category.text.trim();

    // Half and quarter are read first and separately: they are optional, and
    // an optional field needs its own error message. Letting them fall through
    // to the shared validator made an optional field report a required field's
    // problem.
    Money? halfPrice;
    Money? quarterPrice;
    try {
      halfPrice = _optionalPrice(_halfPrice, 'Half price');
      quarterPrice = _optionalPrice(_quarterPrice, 'Quarter price');
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }

    final cost = double.tryParse(_cost.text.trim());
    final price = double.tryParse(_price.text.trim());
    final stock = double.tryParse(_stock.text.trim());
    final reorder = int.tryParse(_reorder.text.trim());
    final bottleMl = int.tryParse(_bottleMl.text.trim());

    if (cost == null || price == null || stock == null) {
      setState(() => _error = cost == null
          ? 'Cost price must be a number'
          : price == null
              ? 'Sell price must be a number'
              : 'Stock must be a number');
      return;
    }

    // Single shared rule set, identical to the Excel and Sheets importers, so
    // the editor cannot persist a row the app's own backup format rejects.
    final problem = Product.validate(
      name: name,
      category: category,
      costPrice: cost,
      sellPrice: price,
      stockQty: stock,
      reorderLevel: reorder ?? -1,
      bottleMl: bottleMl ?? 0,
      halfPrice: halfPrice?.asMajor,
      quarterPrice: quarterPrice?.asMajor,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (price < cost) {
      final proceed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text('Sell price is below cost'),
                content: Text(
                    '$name would sell at a loss (KSh $price vs cost KSh $cost). Save anyway?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Go back')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Save anyway')),
                ],
              ));
      if (proceed != true) return;
    }

    // A variant with no name cannot be sold, priced or scanned, and one that
    // slipped through the form's validation would sit in the catalogue as a row
    // nobody can choose at the till.
    final unnamed = _drafts.indexWhere((draft) => draft.name.trim().isEmpty);
    if (unnamed >= 0) {
      setState(() => _error =
          'Give every variant a name — one of them has none (position ${unnamed + 1}).');
      return;
    }

    setState(() => _error = null);
    final product = Product(
      id: widget.existing?.id,
      name: name,
      category: category,
      // Prices arrive from text fields, so they are whole shillings typed by a
      // human and are quantised once here.
      costPrice: Money.fromMajor(cost),
      sellPrice: Money.fromMajor(price),
      stockQty: stock,
      reorderLevel: reorder ?? 0,
      bottleMl: bottleMl ?? 750,
      // Both read from the row rather than from the passed-in product, because
      // `Product.fromMap` leaves them at their defaults — writing them from a
      // product that came out of the database would switch off "sold as
      // variants" and reset the unit on every unrelated edit.
      unit: _unit,
      trackVariants: _trackVariants,
      // Already `Money`, so they pass straight through. Re-quantising here
      // would be the third conversion on the same value.
      halfPrice: halfPrice,
      quarterPrice: quarterPrice,
      exciseStampBatch: _stamp.text.trim(),
      active: widget.existing?.active ?? true,
      updatedAt: DateTime.now().toIso8601String(),
      remoteId: widget.existing?.remoteId,
    );
    try {
      // The product first: `product_variants.product_id` is NOT NULL, so a
      // variant has nowhere to point until this row exists.
      final productId = await DatabaseHelper.instance.upsertProduct(product);
      // Then the variants, still inside this same dialog session — the owner
      // configured "Kenyana Beer" and its four variants as one thing, and
      // saving half of it would leave the till offering something the catalogue
      // does not have.
      await _saveVariants(productId);
      await _rememberSize(_unit == ProductUnit.each ? 0 : (bottleMl ?? 0));
      // The sell tab is kept alive in an IndexedStack and would otherwise keep
      // selling the catalogue as it was before this save.
      if (mounted) context.read<HomeShellTabs>().markCatalogueChanged();
      widget.onSaved();
      if (mounted) Navigator.pop(context);
      // Push just this row to the backend after the editor closes. A price
      // change left only on the till would let the next till — or the web
      // report — keep selling at the old price until the next auto-sync, which
      // is up to six hours away. Best effort: a failed push is retried by the
      // next bulk sync, and must not turn a local save into an error.
      unawaited(_pushProductInBackground(product));
    } on StateError catch (error) {
      // A staged barcode clash names itself, because it is the owner's code that
      // is already spoken for and the message has to say by whom.
      if (mounted) setState(() => _error = error.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            "Couldn't save — check the phone has storage space free, then try again.");
      }
    }
  }

  /// Pushes the saved row to the backend, re-reading it so the local id and any
  /// newly assigned remote id are included.
  static Future<void> _pushProductInBackground(Product saved) async {
    try {
      if (saved.id == null) return;
      final all = await DatabaseHelper.instance.getProducts(activeOnly: false);
      final fresh = all.where((p) => p.id == saved.id).firstOrNull;
      await BackendService.syncProductToBackend(fresh ?? saved);
    } catch (_) {
      // Offline, unlinked or the backend rejected it: the bulk auto-sync path
      // will pick the change up. Never block the local save on the network.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.existing == null ? 'Add product' : 'Edit product',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name')),
              TextField(
                  controller: _category,
                  decoration: const InputDecoration(labelText: 'Category')),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _cost,
                        decoration:
                            const InputDecoration(labelText: 'Cost price'),
                        keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: _price,
                        decoration:
                            const InputDecoration(labelText: 'Sell price'),
                        keyboardType: TextInputType.number)),
              ]),
              TextField(
                  controller: _bottleMl,
                  decoration: const InputDecoration(
                      labelText: 'Size (ml)',
                      helperText: 'Bottle, keg or tank — 330, 500, 50000'),
                  keyboardType: TextInputType.number),
              if (_visibleSizeSuggestions.isNotEmpty) _sizeSuggestionChips(),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _halfPrice,
                        decoration: const InputDecoration(
                            labelText: 'Half price (optional)'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: _quarterPrice,
                        decoration: const InputDecoration(
                            labelText: 'Quarter price (optional)'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true))),
              ]),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _stock,
                        decoration: InputDecoration(
                            labelText: _trackVariants
                                ? 'Total stock (from variants)'
                                : 'Stock qty',
                            helperText: _trackVariants
                                ? 'The variants\' total, kept in step for you'
                                : null),
                        keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: _reorder,
                        decoration:
                            const InputDecoration(labelText: 'Reorder level'),
                        keyboardType: TextInputType.number)),
              ]),
              TextField(
                  controller: _stamp,
                  decoration: const InputDecoration(
                      labelText: 'Excise stamp batch (optional)')),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _trackVariants,
                onChanged: _setTrackVariants,
                title: const Text('Sold as variants'),
                // Says what turning it on does to the till, because the switch
                // is otherwise invisible in its consequences: with it on, the
                // product itself stops being sellable and its variants take over.
                subtitle: Text(_trackVariants
                    ? 'The till offers Dark, Regular, Big cup… instead of the whole product'
                    : 'For Dark and Regular, or a big cup and a small cup, at different prices'),
              ),
              if (_trackVariants) ...[
                Text('Variants', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                if (_loadingMeta)
                  const LinearProgressIndicator()
                else if (_drafts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                        'No variants yet. The till will ask for one instead of '
                        'selling the whole product.',
                        style: TextStyle(fontSize: 13)),
                  )
                else
                  for (var i = 0; i < _drafts.length; i++) _variantRow(i),
                OutlinedButton.icon(
                  onPressed: _addVariant,
                  icon: const Icon(Icons.add),
                  label: Text(_drafts.isEmpty
                      ? 'Add its first variant'
                      : 'Add another variant'),
                ),
                const SizedBox(height: 16),
              ],
              Text('Barcodes', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'A code on the product adds the whole product. A code on a '
                'variant — entered in that variant\'s own form — adds that '
                'variant, at its price and from its stock. Each code can only '
                'ever resolve to one of them.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              if (_loadingMeta)
                const LinearProgressIndicator()
              else if (_codes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                      'No barcodes yet — this product is sold by name only.',
                      style: TextStyle(fontSize: 13)),
                )
              else
                for (final code in _codes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                        code.isVariantLevel
                            ? Icons.label_outline
                            : Icons.qr_code,
                        size: 20),
                    title: Text(code.barcode,
                        style: const TextStyle(fontFamily: 'monospace')),
                    // The level is named, not implied: "this code adds the
                    // whole product" and "this code adds Dark" behave
                    // differently at the till and the owner has to be able to
                    // tell which they are looking at.
                    subtitle: Text(
                        '${code.scopeLabel} · ${BarcodeKind.label(code.kind)}'),
                    // Relabelling is a tap rather than a dropdown because there
                    // are three kinds and only one reason to change them; the
                    // affordance is discoverable without a dialog.
                    onTap: () => _cycleBarcodeKind(code),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Remove ${code.barcode}',
                      onPressed: () => _removeBarcode(code),
                    ),
                  ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _barcode,
                    decoration: const InputDecoration(
                        labelText: 'Add a barcode', hintText: '6001234567892'),
                    // Digits and letters only: what a scanner could emit.
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9\-]')),
                    ],
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => _addBarcode(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add barcode',
                  onPressed: _addBarcode,
                ),
              ]),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _save,
                  // Says what the button will do: on a product with variants
                  // staged, this is one save of the product *and* them, not a
                  // save of the product alone.
                  child: Text(_trackVariants && _drafts.isNotEmpty
                      ? 'Save product and ${_drafts.length} variant${_drafts.length == 1 ? '' : 's'}'
                      : 'Save product')),
              const SizedBox(height: 16),
            ]),
      ),
    );
  }
}

class _AdjustDialog extends StatefulWidget {
  final Product product;

  /// Set when the correction applies to one variant rather than the product.
  final ProductVariant? variant;

  const _AdjustDialog({required this.product, this.variant});
  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _delta = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _delta.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.variant == null
          ? 'Adjust stock — ${widget.product.name}'
          : 'Adjust stock — ${widget.variant!.label}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: _delta,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: const InputDecoration(
                labelText: 'Change (+50 restock, -2 breakage)')),
        TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason')),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
              context, {'delta': _delta.text, 'reason': _reason.text}),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
