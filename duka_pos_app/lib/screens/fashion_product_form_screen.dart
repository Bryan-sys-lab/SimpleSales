import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../services/barcode/barcode_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';
import '../ui/components/product_photo.dart';
import '../services/product_image_store.dart';
import '../services/workspace_service.dart';
import '../utils/money.dart';
import '../utils/units.dart';
import '../widgets/backup_reminder_banner.dart';
import '../widgets/variant_catalogue.dart';

const double _fashionProductFormMaxWidth = 900;

/// Create or edit a fashion style with variants.
///
/// Sections: product identity (name and category), variants (size, SKU, barcode,
/// stock, sell price, cost price, reorder level).
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

  final List<_VariantEditor> _variants = [];
  bool _saving = false;
  bool _loading = false;
  Product? _product;
  File? _pickedPhoto;
  bool _photoRemoved = false;

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
      final codes = await VariantCatalogue.codesForProduct(pid);
      final codesByVariant = <int, String>{
        for (final code in codes)
          if (code.variantId != null) code.variantId!: code.barcode,
      };
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
          if (v.sizeMl > 0) e.sizeCtrl.text = v.sizeMl.toString();
          e.skuCtrl.text = v.sku;
          e.storedBarcode = codesByVariant[v.id];
          e.barcodeCtrl.text = e.storedBarcode ?? '';
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
      final variantEditors =
          _variants.where((v) => v.nameCtrl.text.trim().isNotEmpty).toList();

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
      final existingCodes = <int, String>{};
      final pid = _product?.id;
      if (pid != null) {
        existingVariants.addAll(await db.getVariants(pid, activeOnly: false));
        for (final code in await VariantCatalogue.codesForProduct(pid)) {
          if (code.variantId != null) {
            existingCodes[code.variantId!] = code.barcode;
          }
        }
      }
      final requestedCodes = <String, _VariantEditor>{};
      for (final v in variantEditors) {
        final rawCode = v.barcodeCtrl.text.trim();
        if (rawCode.isEmpty) continue;
        final code = Barcode.normalise(rawCode);
        if (!Barcode.isValid(code)) {
          throw StateError('Barcode must be 6–64 valid characters');
        }
        if (requestedCodes.containsKey(code)) {
          throw StateError('Each variant barcode must be unique');
        }
        requestedCodes[code] = v;
      }
      var savedProductId = pid;
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
          imagePath: _product?.imagePath,
        );
        final productId = await db.upsertProductInTransaction(txn, product);
        savedProductId = productId;

        final keptVariantIds = <int>{};
        for (final v in variantEditors) {
          final variant = ProductVariant(
            id: v.variantId,
            productId: productId,
            name: v.nameCtrl.text.trim(),
            sku: v.skuCtrl.text.trim(),
            unit: (int.tryParse(v.sizeCtrl.text.trim()) ?? 0) > 0
                ? ProductUnit.millilitre
                : ProductUnit.each,
            sizeMl: int.tryParse(v.sizeCtrl.text.trim()) ?? 0,
            sellPrice: Money.fromMajor(
              parseMoneyInput(v.sellPriceCtrl.text) ?? 0,
            ),
            costPrice: Money.fromMajor(
              parseMoneyInput(v.costPriceCtrl.text) ?? 0,
            ),
            stockQty: double.tryParse(v.stockCtrl.text) ?? 0,
            reorderLevel: int.tryParse(v.reorderCtrl.text) ?? 0,
          );
          final savedId = await db.upsertVariantInTransaction(txn, variant);
          if (savedId > 0) {
            v.variantId = savedId;
            keptVariantIds.add(savedId);
          }
        }

        for (final existing in existingVariants) {
          if (!keptVariantIds.contains(existing.id!)) {
            await db.deleteVariantInTransaction(txn, existing.id!);
          }
        }
      });

      // Barcode rows are deliberately separate from variant upserts. Reconcile
      // them only after the variant transaction succeeds, preserving existing
      // codes when a save fails.
      if (savedProductId != null) {
        for (final oldCode in existingCodes.values) {
          await db.removeBarcode(oldCode);
        }
        for (final v in variantEditors) {
          final code = Barcode.normalise(v.barcodeCtrl.text.trim());
          if (code.isEmpty || v.variantId == null) continue;
          if (!await db.addBarcode(
              productId: savedProductId!,
              variantId: v.variantId,
              barcode: code)) {
            throw StateError('Barcode $code is already in use');
          }
        }
        await VariantCatalogue.writeAggregateStock(savedProductId!);

        if (_pickedPhoto != null || _photoRemoved) {
          final workspaceKey = await WorkspaceService.activeWorkspaceKey();
          if (_photoRemoved) {
            await ProductImageStore.delete(
              savedProductId!,
              workspaceKey: workspaceKey,
            );
            await db.setProductImage(null, savedProductId!);
          } else {
            final relative = await ProductImageStore.save(
              _pickedPhoto!,
              productId: savedProductId!,
              workspaceKey: workspaceKey,
            );
            await db.setProductImage(relative, savedProductId!);
          }
        }
      }

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

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 90,
    );
    if (!mounted || file == null) return;
    setState(() {
      _pickedPhoto = File(file.path);
      _photoRemoved = false;
    });
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
          SizedBox(height: spacing.md),
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
                FormFieldGroup(
                  children: <Widget>[
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.fashionProductFormStyleName,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? l10n.fashionProductFormStyleNameRequired
                          : null,
                    ),
                    TextFormField(
                      controller: _categoryCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.fashionProductFormCategory,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: spacing.md),
                SurfaceCard(
                  padding: EdgeInsets.all(spacing.md),
                  child: Row(
                    children: <Widget>[
                      ProductPhoto(
                        imagePath: _pickedPhoto == null
                            ? (_photoRemoved ? null : _product?.imagePath)
                            : null,
                        size: 72,
                        revision: _product?.updatedAt,
                      ),
                      SizedBox(width: spacing.md),
                      Expanded(
                        child: Text(
                          'Style photo',
                          style: type.titleSmall,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickPhoto,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: Text(_pickedPhoto == null ? 'Add' : 'Replace'),
                      ),
                      if (_product?.imagePath != null || _pickedPhoto != null)
                        IconButton(
                          tooltip: 'Remove photo',
                          onPressed: () => setState(() {
                            _pickedPhoto = null;
                            _photoRemoved = true;
                          }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
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
  String? storedBarcode;
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
      'sell_price': parseMoneyInput(sellPriceCtrl.text) ?? 0,
      'cost_price': parseMoneyInput(costPriceCtrl.text) ?? 0,
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
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 600;

              Widget field(Widget child) => narrow
                  ? Padding(
                      padding: EdgeInsets.only(bottom: spacing.md),
                      child: child,
                    )
                  : Expanded(child: child);

              Widget row(List<Widget> fields) => narrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: fields,
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < fields.length; i++) ...[
                          if (i > 0) SizedBox(width: spacing.sm),
                          fields[i],
                        ],
                      ],
                    );

              final identity = row([
                field(TextFormField(
                  controller: variant.nameCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormVariantName,
                  ),
                )),
                field(TextFormField(
                  controller: variant.sizeCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormSize,
                  ),
                )),
                field(TextFormField(
                  controller: variant.colourCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormColour,
                  ),
                )),
              ]);
              final codes = row([
                field(TextFormField(
                  controller: variant.skuCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormSKU,
                  ),
                )),
                field(TextFormField(
                  controller: variant.barcodeCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormBarcode,
                  ),
                )),
              ]);
              final stock = row([
                field(TextFormField(
                  controller: variant.stockCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormStock,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                )),
                field(TextFormField(
                  controller: variant.sellPriceCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormSellPrice,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                )),
                field(TextFormField(
                  controller: variant.costPriceCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormCostPrice,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                )),
                field(TextFormField(
                  controller: variant.reorderCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fashionProductFormReorderLevel,
                  ),
                  keyboardType: TextInputType.number,
                )),
              ]);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: identity),
                      SizedBox(width: spacing.sm),
                      IconButton(
                        tooltip: 'Remove variant',
                        icon: Icon(Icons.remove, color: colors.danger),
                        onPressed: onRemove,
                      ),
                    ],
                  ),
                  SizedBox(height: spacing.sm),
                  codes,
                  SizedBox(height: spacing.sm),
                  stock,
                ],
              );
            },
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
