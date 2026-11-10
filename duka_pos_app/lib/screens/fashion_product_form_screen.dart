import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../utils/units.dart';
import '../widgets/backup_reminder_banner.dart';

const double _fashionProductFormMaxWidth = 900;

/// Create or edit a fashion style with variants.
///
/// Sections: product identity (name, category, brand, description), variants
/// (size, colour, SKU, barcode, stock, sell price, cost price, reorder level).
/// Variants can be added one at a time — no forced size × colour matrix.
class FashionProductFormScreen extends StatefulWidget {
  const FashionProductFormScreen({super.key, this.product, this.productId});

  final Product? product;
  final int? productId;

  @override
  State<FashionProductFormScreen> createState() =>
      _FashionProductFormScreenState();
}

class _FashionProductFormScreenState extends State<FashionProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  final List<_VariantEditor> _variants = [];
  bool _saving = false;
  bool _loading = false;
  Product? _product;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    if (_product != null) {
      _nameCtrl.text = _product!.name;
      _categoryCtrl.text = _product!.category;
    }
    final int? pid = widget.productId ?? widget.product?.id;
    if (pid != null) {
      _loading = true;
      _loadExisting(pid);
    } else {
      // Start with one empty variant.
      _addVariant();
    }
  }

  Future<void> _loadExisting(int pid) async {
    try {
      final db = DatabaseHelper.instance;
      final p = await db.getProductById(pid);
      if (!mounted) return;
      if (p != null) {
        _product = p;
        _nameCtrl.text = p.name;
        _categoryCtrl.text = p.category;
      }
      final variants = await db.getVariants(pid, activeOnly: false);
      if (!mounted) return;
      for (final v in _variants) {
        v.dispose();
      }
      _variants.clear();
      if (variants.isEmpty) {
        _addVariant();
      } else {
        for (final v in variants) {
          final e = _VariantEditor();
          e.variantId = v.id;
          e.productId = v.productId;
          e.nameCtrl.text = v.name;
          e.skuCtrl.text = v.sku;
          e.stockCtrl.text = v.stockQty.toString();
          e.sellPriceCtrl.text = v.sellPrice.asMajor.toString();
          e.costPriceCtrl.text = v.costPrice.asMajor.toString();
          e.reorderCtrl.text = v.reorderLevel.toString();
          setState(() => _variants.add(e));
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _brandCtrl.dispose();
    _descriptionCtrl.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  void _addVariant() {
    setState(() {
      _variants.add(_VariantEditor());
    });
  }

  void _removeVariant(int index) {
    setState(() {
      _variants[index].dispose();
      _variants.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final variantEditors = _variants
          .where((v) => v.nameCtrl.text.trim().isNotEmpty)
          .toList();

      if (variantEditors.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add at least one variant.'),
        ));
        setState(() => _saving = false);
        return;
      }

      final db = DatabaseHelper.instance;
      final existingVariants = <ProductVariant>[];
      final pid = _product?.id;
      if (pid != null) {
        existingVariants.addAll(await db.getVariants(pid, activeOnly: false));
      }
      await (await db.database).transaction((txn) async {
        final product = Product(
          id: _product?.id,
          name: _nameCtrl.text.trim(),
          category: _categoryCtrl.text.trim(),
          costPrice: Money.zero,
          sellPrice: Money.zero,
          stockQty: 0,
          reservedQty: 0,
          reorderLevel: 0,
          bottleMl: 0,
          unit: ProductUnit.each,
          millilitresPerKilogram: 0,
          trackVariants: true,
          trackExpiry: false,
          active: true,
          updatedAt: DateTime.now().toIso8601String(),
        );
        final productId = await db.upsertProductInTransaction(txn, product);

        final keptVariantIds = <int>{};
        for (final v in variantEditors) {
          final variant = ProductVariant(
            id: v.variantId,
            productId: productId,
            name: v.nameCtrl.text.trim(),
            sku: v.skuCtrl.text.trim(),
            unit: ProductUnit.each,
            sizeMl: 0,
            sellPrice: Money.fromMajor(
              double.tryParse(v.sellPriceCtrl.text) ?? 0,
            ),
            costPrice: Money.fromMajor(
              double.tryParse(v.costPriceCtrl.text) ?? 0,
            ),
            stockQty: double.tryParse(v.stockCtrl.text) ?? 0,
            reorderLevel: int.tryParse(v.reorderCtrl.text) ?? 0,
          );
          final savedId = await db.upsertVariantInTransaction(txn, variant);
          if (savedId > 0) keptVariantIds.add(savedId);
        }

        for (final existing in existingVariants) {
            if (!keptVariantIds.contains(existing.id!)) {
              await db.deleteVariantInTransaction(txn, existing.id!);
            }
          }
      });

      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Save failed: $e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final type = AppTypography.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return AdaptivePage(
      scrollable: true,
      maxContentWidth: _fashionProductFormMaxWidth,
      padding: PageGutter.of(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          BackupReminderBanner(onBackupNow: () => performBackup(context)),
          SizedBox(height: spacing.section),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _product == null
                          ? l10n.fashionProductFormAddStyle
                          : l10n.fashionProductFormEditStyle,
                      style: AppTypography.of(context).headlineSmall,
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      _product == null
                          ? l10n.fashionProductFormAddStyleSubtitle
                          : l10n.fashionProductFormEditStyleSubtitle,
                      style: type.bodyMedium?.copyWith(
                        color: colors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Section A: Product identity
                _SectionHeader(
                  title: l10n.fashionProductFormProductInfo,
                ),
                SizedBox(height: spacing.sm),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormStyleName,
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty
                          ? l10n.fashionProductFormStyleNameRequired
                          : null,
                ),
                SizedBox(height: spacing.sm),
                TextFormField(
                  controller: _categoryCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormCategory,
                  ),
                ),
                SizedBox(height: spacing.sm),
                TextFormField(
                  controller: _brandCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormBrand,
                  ),
                ),
                SizedBox(height: spacing.sm),
                TextFormField(
                  controller: _descriptionCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormDescription,
                  ),
                  maxLines: 2,
                ),
                SizedBox(height: spacing.lg),

                // Section B: Variants
                _SectionHeader(
                  title: l10n.fashionProductFormVariants,
                  trailing: OutlinedButton.icon(
                    onPressed: _addVariant,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.fashionProductFormAddVariant),
                  ),
                ),
                SizedBox(height: spacing.sm),
                ..._variants.asMap().entries.map((entry) {
                  final index = entry.key;
                  final variant = entry.value;
                  return Padding(
                    padding: EdgeInsets.only(bottom: spacing.sm),
                    child: _VariantCard(
                      variant: variant,
                      onRemove: () => _removeVariant(index),
                    ),
                  );
                }),
                SizedBox(height: spacing.lg),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Saving…' : 'Save style'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One variant editor row: size, colour, SKU, barcode, stock, prices.
class _VariantEditor {
  int? variantId;
  int? productId;
  final nameCtrl = TextEditingController();
  final sizeCtrl = TextEditingController();
  final colourCtrl = TextEditingController();
  final skuCtrl = TextEditingController();
  final barcodeCtrl = TextEditingController();
  final stockCtrl = TextEditingController(text: '0');
  final sellPriceCtrl = TextEditingController();
  final costPriceCtrl = TextEditingController();
  final reorderCtrl = TextEditingController(text: '0');

  void dispose() {
    nameCtrl.dispose();
    sizeCtrl.dispose();
    colourCtrl.dispose();
    skuCtrl.dispose();
    barcodeCtrl.dispose();
    stockCtrl.dispose();
    sellPriceCtrl.dispose();
    costPriceCtrl.dispose();
    reorderCtrl.dispose();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': variantId,
      'product_id': productId,
      'name': nameCtrl.text.trim(),
      'size': sizeCtrl.text.trim(),
      'colour': colourCtrl.text.trim(),
      'sku': skuCtrl.text.trim(),
      'barcode': barcodeCtrl.text.trim(),
      'stock': double.tryParse(stockCtrl.text) ?? 0,
      'sell_price': double.tryParse(sellPriceCtrl.text) ?? 0,
      'cost_price': double.tryParse(costPriceCtrl.text) ?? 0,
      'reorder_level': int.tryParse(reorderCtrl.text) ?? 0,
    };
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({required this.variant, required this.onRemove});

  final _VariantEditor variant;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final l10n = AppLocalizations.of(context);

    return SurfaceCard(
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: variant.nameCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormVariantName,
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: TextFormField(
                  controller: variant.sizeCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormSize,
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: TextFormField(
                  controller: variant.colourCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormColour,
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              IconButton(
                icon: Icon(Icons.remove, color: colors.danger),
                onPressed: onRemove,
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: variant.skuCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormSKU,
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: TextFormField(
                  controller: variant.barcodeCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormBarcode,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: variant.stockCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormStock,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: TextFormField(
                  controller: variant.sellPriceCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormSellPrice,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: TextFormField(
                  controller: variant.costPriceCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormCostPrice,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: TextFormField(
                  controller: variant.reorderCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormReorderLevel,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final type = AppTypography.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: type.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
