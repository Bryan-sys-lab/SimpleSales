// The "add/edit variant" form, and the draft it produces.
//
// A draft rather than a [ProductVariant] because a variant cannot be saved on
// its own: `product_variants.product_id` is NOT NULL, so the product row has to
// exist first. The product editor therefore collects drafts through this sheet
// and writes them in the same dialog session, after the product. That also means
// a variant the owner typed but then abandoned never reaches the catalogue.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../services/barcode/barcode_service.dart';
import '../utils/money.dart';
import '../utils/units.dart';

/// One variant as the editor currently holds it.
///
/// [id] is null for a variant the owner has just typed: it has never been
/// written, so it has no row and no barcode of its own yet.
class VariantDraft {
  const VariantDraft({
    this.id,
    required this.name,
    this.sku = '',
    this.unit = ProductUnit.each,
    this.sizeMl = 0,
    required this.sellPrice,
    this.costPrice = Money.zero,
    this.stockQty = 0,
    this.reorderLevel = 0,
    this.position = 0,
    this.active = true,
    this.barcode = '',
    this.storedBarcode = '',
  });

  /// A new variant that starts from what the parent already says.
  ///
  /// Adding "Dark" to "Kenyana Beer" is then two fields — the name and the
  /// price if it differs — instead of eight retyped ones. Cost and price are
  /// the parent's, the unit is the parent's, and the serving size starts at the
  /// parent's bottle size, which is right far more often than not.
  factory VariantDraft.seededFrom({
    required Product parent,
    required ProductUnit parentUnit,
    int position = 0,
  }) =>
      VariantDraft(
        name: '',
        unit: parentUnit,
        sizeMl: parentUnit == ProductUnit.each ? 0 : parent.bottleMl,
        sellPrice: parent.sellPrice,
        costPrice: parent.costPrice,
        stockQty: 0,
        reorderLevel: parent.reorderLevel,
        position: position,
      );

  /// An existing variant, carried through the form unchanged except for what
  /// the owner edits.
  ///
  /// [storedBarcode] is the code already attached to this variant in the
  /// table, kept so a save can tell an edited code from an unchanged one and
  /// only write when something actually changed.
  factory VariantDraft.fromVariant(
    ProductVariant variant, {
    String storedBarcode = '',
  }) =>
      VariantDraft(
        id: variant.id,
        name: variant.name,
        sku: variant.sku,
        unit: variant.unit,
        sizeMl: variant.sizeMl,
        sellPrice: variant.sellPrice,
        costPrice: variant.costPrice,
        stockQty: variant.stockQty,
        reorderLevel: variant.reorderLevel,
        position: variant.position,
        active: variant.active,
        storedBarcode: storedBarcode,
        barcode: storedBarcode,
      );

  final int? id;
  final String name;
  final String sku;
  final ProductUnit unit;
  final int sizeMl;
  final Money sellPrice;
  final Money costPrice;
  final double stockQty;
  final int reorderLevel;
  final int position;
  final bool active;

  /// The code as it now stands — typed, or carried in from storage.
  final String barcode;

  /// The code as it is in the table, which may differ from [barcode] because
  /// the owner just changed it.
  final String storedBarcode;

  bool get isNew => id == null;
  bool get hasStoredBarcode => storedBarcode.trim().isNotEmpty;
  bool get barcodeChanged => barcode.trim() != storedBarcode.trim();

  /// The size as the owner reads it, or empty for a countable variant.
  ///
  /// `Volume.display` is the same renderer the till uses, so what the editor
  /// shows is what the cashier will see. A countable variant has no size at
  /// all, and printing "0 ml" would invent one.
  String get sizeLabel => unit == ProductUnit.each || sizeMl <= 0
      ? ''
      : Volume(sizeMl.toDouble()).display;

  /// The variant this draft becomes once its product has a row.
  ProductVariant toVariant(int productId) => ProductVariant(
        id: id,
        productId: productId,
        name: name.trim(),
        sku: sku.trim(),
        unit: unit,
        // A countable variant stores no size: `size_ml` means "how big one is",
        // and for "Dark" that question has no answer.
        sizeMl: unit == ProductUnit.each ? 0 : sizeMl,
        sellPrice: sellPrice,
        costPrice: costPrice,
        stockQty: stockQty,
        reorderLevel: reorderLevel,
        position: position,
        active: active,
      );

  VariantDraft copyWith({
    int? id,
    String? name,
    String? sku,
    ProductUnit? unit,
    int? sizeMl,
    Money? sellPrice,
    Money? costPrice,
    double? stockQty,
    int? reorderLevel,
    int? position,
    bool? active,
    String? barcode,
    String? storedBarcode,
  }) =>
      VariantDraft(
        id: id ?? this.id,
        name: name ?? this.name,
        sku: sku ?? this.sku,
        unit: unit ?? this.unit,
        sizeMl: sizeMl ?? this.sizeMl,
        sellPrice: sellPrice ?? this.sellPrice,
        costPrice: costPrice ?? this.costPrice,
        stockQty: stockQty ?? this.stockQty,
        reorderLevel: reorderLevel ?? this.reorderLevel,
        position: position ?? this.position,
        active: active ?? this.active,
        barcode: barcode ?? this.barcode,
        storedBarcode: storedBarcode ?? this.storedBarcode,
      );
}

/// Shows the variant form and returns the draft it produced, or null if the
/// owner backed out.
///
/// [parentProductId] scopes which remembered cup sizes are offered. It is null
/// when the parent product has never been written — a variant can be typed
/// before its product row exists — and in that case the shop-wide sizes are
/// offered instead, because those are the ones that generalise.
Future<VariantDraft?> showVariantFormSheet(
  BuildContext context, {
  required VariantDraft seed,
  String? title,
  int? parentProductId,
}) =>
    showModalBottomSheet<VariantDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VariantFormSheet(
        seed: seed,
        title: title,
        parentProductId: parentProductId,
      ),
    );

/// The variant form itself.
///
/// A bottom sheet rather than a dialog because it is a scrollable stack of
/// fields and a keyboard, which is exactly the case `isScrollControlled` plus
/// a viewInsets-aware scroll view exists for.
class VariantFormSheet extends StatefulWidget {
  const VariantFormSheet({
    super.key,
    required this.seed,
    this.title,
    this.parentProductId,
  });

  final VariantDraft seed;
  final String? title;

  /// The product this variant belongs to, when it already has a row.
  final int? parentProductId;

  @override
  State<VariantFormSheet> createState() => _VariantFormSheetState();
}

class _VariantFormSheetState extends State<VariantFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _stock;
  late final TextEditingController _reorder;
  late final TextEditingController _size;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  String? _error;
  bool _saving = false;

  /// Cup sizes this shop has used before, most-used first.
  ///
  /// Shown as one-tap chips under the serving size so a beer shop stops
  /// retyping "330" on every keg it sells. Loaded once on open rather than per
  /// keystroke: this is a short list behind a database read, and a rebuild per
  /// character would be visible on a cheap till.
  List<CupSizeSuggestion> _suggestions = const [];

  /// How many chips to offer.
  ///
  /// Bounded because a chip row that wraps to four lines pushes the save button
  /// under the keyboard on a small phone. The most-used sizes are the ones worth
  /// the space, and they are already sorted that way.
  static const _maxSuggestions = 6;

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    _name = TextEditingController(text: seed.name);
    _price = TextEditingController(text: editVariantAmount(seed.sellPrice));
    // An empty cost field means "same as the product", so the *parent's* cost is
    // seeded rather than the variant's own — otherwise editing a variant that
    // was never given a cost silently shows "0" as if that were its cost.
    _cost = TextEditingController(text: editVariantAmount(seed.costPrice));
    _stock = TextEditingController(text: editVariantQuantity(seed.stockQty));
    _reorder = TextEditingController(text: seed.reorderLevel.toString());
    _size = TextEditingController(text: seed.sizeLabel);
    _sku = TextEditingController(text: seed.sku);
    _barcode = TextEditingController(text: seed.barcode);
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final db = DatabaseHelper.instance;
    final id = widget.parentProductId;
    final loaded = id == null
        ? await db.getCupSizeSuggestions()
        : await db.getCupSizeSuggestionsForProduct(id);
    if (!mounted) return;
    setState(() => _suggestions = loaded);
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _cost.dispose();
    _stock.dispose();
    _reorder.dispose();
    _size.dispose();
    _sku.dispose();
    _barcode.dispose();
    super.dispose();
  }

  /// The size chips worth offering for the unit currently chosen.
  ///
  /// A countable variant has no size, so offering ml chips under it would be
  /// offering an answer to a question nobody asked. Cups and litres get them.
  List<CupSizeSuggestion> get _visibleSuggestions => _suggestions;

  /// A remembered size as the owner reads it, using the same renderer the
  /// serving-size field parses, so tapping a chip and typing it agree.
  String _suggestionLabel(CupSizeSuggestion s) =>
      Volume(s.sizeMl.toDouble()).display;

  /// The derived unit: volumetric when a size is set, countable otherwise.
  ProductUnit _unitFor(int sizeMl) =>
      sizeMl > 0 ? ProductUnit.millilitre : ProductUnit.each;

  void _useSuggestion(CupSizeSuggestion s) {
    final text = _suggestionLabel(s);
    _size.text = text;
    // Nothing else about the draft changes, and the field already shows the
    // value, so no setState is needed to redraw it. The keyboard stays up.
  }

  Future<void> _submit() async {
    // A double-tap on save would otherwise record the cup size twice, and the
    // suggestion list is ranked by use count — so one impatient cashier would
    // permanently float a size to the top of every shop's list.
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _submitDraft();
    } finally {
      // Only reached when validation or the write failed; a successful submit
      // pops the sheet and this state object goes with it.
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitDraft() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.variantNameRequired);
      return;
    }
    if (name.length > Product.maxNameLength) {
      setState(() => _error = l10n.variantNameTooLong(Product.maxNameLength));
      return;
    }

    final price = double.tryParse(_price.text.trim());
    if (price == null) {
      setState(() => _error = l10n.variantSellPriceNotANumber);
      return;
    }
    if (!Money.isValidMajor(price)) {
      setState(() => _error = l10n.variantSellPriceNotNegative);
      return;
    }

    // Cost is optional in the field but not in the row: an empty field means
    // "the same as the product", and the seed already holds that. An
    // *unparseable* field is an error rather than a silent fallback — the same
    // distinction the product editor draws, and for the same reason: a price
    // that fails to parse used to be written back as nothing.
    var cost = widget.seed.costPrice;
    final costText = _cost.text.trim();
    if (costText.isNotEmpty) {
      final parsed = double.tryParse(costText);
      if (parsed == null) {
        setState(
          () => _error = l10n.variantCostPriceNotANumber(
            formatMoney(widget.seed.costPrice),
          ),
        );
        return;
      }
      if (!Money.isValidMajor(parsed)) {
        setState(() => _error = l10n.variantCostPriceNotNegative);
        return;
      }
      cost = Money.fromMajor(parsed);
    }

    final stock = double.tryParse(_stock.text.trim());
    if (stock == null || !stock.isFinite || stock < 0) {
      setState(() => _error = l10n.validationStockNotNegative);
      return;
    }
    final reorder = int.tryParse(_reorder.text.trim()) ?? 0;
    if (reorder < 0) {
      setState(() => _error = l10n.variantReorderLevelNotNegative);
      return;
    }

    var sizeMl = widget.seed.sizeMl;
    final raw = _size.text.trim();
    if (raw.isEmpty) {
      sizeMl = 0;
    } else {
      // The owner's own words, through the one parser the importers and the
      // till share: "500ml", "0.5 L" and "0.5litre" all mean the same size.
      final volume = Volume.parse(raw, declared: ProductUnit.millilitre);
      if (!volume.isValid) {
        setState(() => _error = l10n.variantSizeInvalid);
        return;
      }
      sizeMl = volume.rounded;
      if (sizeMl < Product.minBottleMl || sizeMl > Product.maxBottleMl) {
        setState(() => _error = l10n.variantSizeInvalid);
        return;
      }
    }

    var barcode = '';
    final rawCode = _barcode.text.trim();
    if (rawCode.isNotEmpty) {
      final code = Barcode.normalise(rawCode);
      final problem = Barcode.rejectionReason(code);
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
      barcode = code;
    }

    // Remember any non-zero size so it resurfaces as a one-tap chip. A blank
    // size means countable — nothing to remember.
    if (sizeMl > 0) {
      try {
        await DatabaseHelper.instance.upsertCupSizeSuggestion(
          productId: widget.parentProductId,
          sizeMl: sizeMl,
        );
      } catch (_) {
        // A missed suggestion is not worth blocking a save over. The size is
        // already in the variant row, which is what the till sells.
      }
    }

    if (!mounted) return;
    final unit = _unitFor(sizeMl);
    Navigator.pop(
      context,
      widget.seed.copyWith(
        name: name,
        sku: _sku.text.trim(),
        unit: unit,
        sizeMl: sizeMl,
        sellPrice: Money.fromMajor(price),
        costPrice: cost,
        stockQty: stock,
        reorderLevel: reorder,
        barcode: barcode,
      ),
    );
  }

  /// The serving-size field, always shown: blank means countable.
  Widget _sizeField(AppLocalizations l10n) => TextField(
        controller: _size,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: l10n.variantSizeLabel,
          hintText: l10n.variantSizeHintMillilitre,
          helperText: l10n.variantSizeHelper,
        ),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: false),
      );

  /// One-tap chips for cup sizes this shop has used before.
  ///
  /// A chip is a `Semantics` button with the size as its label, so it reads as
  /// "330 ml" rather than as an unlabelled box, and the whole row is announced
  /// as the group it is. Wrapping rather than scrolling horizontally, because a
  /// horizontally scrolled row hides the sizes the shop uses most — the ones at
  /// the far end are the least used, so hiding them costs nothing.
  Widget _suggestionChips(ThemeData theme, AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Semantics(
          container: true,
          label: l10n.variantSizeSuggestionsSpoken,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in _visibleSuggestions.take(_maxSuggestions))
                ActionChip(
                  label: Text(_suggestionLabel(s)),
                  onPressed: () => _useSuggestion(s),
                ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title ??
                  (widget.seed.isNew
                      ? l10n.variantAddTitle
                      : l10n.variantEditTitle),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: widget.seed.isNew,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.variantNameLabel,
                hintText: l10n.variantNameHint,
              ),
            ),
            const SizedBox(height: 8),
            // The serving-size field is always shown: blank means countable,
            // any value means volumetric (millilitres). A unit dropdown is no
            // longer offered — the unit is derived from whether a size exists.
            _sizeField(l10n),
            if (_visibleSuggestions.isNotEmpty) _suggestionChips(theme, l10n),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      InputDecoration(labelText: l10n.variantSellPriceLabel),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _cost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: l10n.variantCostPriceLabel,
                    hintText: formatMoney(widget.seed.costPrice),
                    helperText: l10n.variantCostPriceHelper(
                      formatMoney(widget.seed.costPrice),
                    ),
                  ),
                ),
              ),
            ]),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _stock,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: l10n.variantStartingStockLabel,
                    helperText: l10n.variantStartingStockHelper,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _reorder,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.variantReorderLevelLabel,
                    helperText: l10n.variantReorderLevelHelper,
                  ),
                ),
              ),
            ]),
            TextField(
              controller: _sku,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.variantSkuLabel,
                helperText: l10n.variantSkuHelper,
              ),
            ),
            TextField(
              controller: _barcode,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
              ],
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.variantBarcodeLabel,
                hintText: l10n.variantBarcodeHint,
                helperText: l10n.variantBarcodeHelper,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              child: Text(widget.seed.isNew
                  ? l10n.variantAddTitle
                  : l10n.variantSaveAction),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// A money value as editable whole shillings, or empty when absent.
///
/// Whole shillings rather than two decimals because that is what these fields
/// accept and what a shopkeeper types; cents appear only when the amount has
/// them, so "500" does not read as "500.00". Mirrors the product editor's own
/// money formatter — one implementation per file rather than a shared one,
/// because these two forms are deliberately independent and neither is the
/// other's fallback.
String editVariantAmount(Money? value) {
  if (value == null) return '';
  final major = value.minorUnits ~/ kMinorUnitsPerMajor;
  final cents = value.minorUnits % kMinorUnitsPerMajor;
  return cents == 0 ? '$major' : '$major.${cents.toString().padLeft(2, '0')}';
}

/// A quantity for editing: no trailing `.0` for a whole number.
String editVariantQuantity(double value) =>
    value % 1 == 0 ? value.toInt().toString() : value.toString();
