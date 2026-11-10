import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';

import 'shop_profile.dart';
import '../models/models.dart';

/// Profile-specific product creation flows.
/// 
/// Each profile gets a tailored add-product flow:
/// - Drinks: bottle/shot/crate/keg (via ProfileProductForms)
/// - Duka: uses shared ProductEditor (see inventory_screen.dart)
/// - Fashion: style/size/colour variants (via ProfileProductForms)
/// - Open: money-first optional stock (via ProfileProductForms)
///
/// Duka no longer uses ProfileProductForms; it routes through the shared
/// ProductEditor widget so dashboard and inventory create/edit through one
/// widget. This keeps a single persistence pipeline (upsertProduct).
class ProfileProductForms {
  const ProfileProductForms();

  /// Creates a product form tailored to the profile.
  /// 
  /// Returns a map of field values keyed by field name.
  /// 
  /// Note: ShopProfile.duka is not handled here — Duka uses ProductEditor
  /// directly (see inventory_screen.dart) so dashboard and inventory share
  /// one editor. Passing ShopProfile.duka returns null.
  static Future<Map<String, dynamic>?> showForm({
    required BuildContext context,
    required ShopProfile profile,
    Product? existingProduct,
  }) async {
    return switch (profile) {
      ShopProfile.drinks => _showDrinksForm(context, existingProduct),
      ShopProfile.fashion => _showFashionForm(context, existingProduct),
      ShopProfile.open => _showOpenForm(context, existingProduct),
      ShopProfile.duka => null, // Duka uses ProductEditor directly
    };
  }

  static Future<Map<String, dynamic>?> _showDrinksForm(
    BuildContext context,
    Product? existing,
  ) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final categoryController = TextEditingController(text: existing?.category ?? 'Drinks');
    final costController = TextEditingController(
        text: existing?.costPrice.asMajor.toStringAsFixed(2) ?? '');
    final priceController = TextEditingController(
        text: existing?.sellPrice.asMajor.toStringAsFixed(2) ?? '');
    final stockController = TextEditingController(
        text: existing?.stockQty.toString() ?? '0');
    final bottleMlController = TextEditingController(
        text: existing?.bottleMl.toString() ?? '750');
    final halfPriceController = TextEditingController(
        text: existing?.halfPrice?.asMajor.toStringAsFixed(2) ?? '');
    final quarterPriceController = TextEditingController(
        text: existing?.quarterPrice?.asMajor.toStringAsFixed(2) ?? '');

    String unit = existing?.unit.wire ?? 'bottle';
    String? packType;

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(AppLocalizations.of(context).profileFormAddDrink),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Drink name'),
                  autofocus: true,
                ),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: [
                    DropdownMenuItem(value: 'bottle', child: Text(AppLocalizations.of(context).profileFormBottle)),
                    DropdownMenuItem(value: 'crate', child: Text(AppLocalizations.of(context).profileFormCrate)),
                    DropdownMenuItem(value: 'keg', child: Text(AppLocalizations.of(context).profileFormKeg)),
                    DropdownMenuItem(value: 'shot', child: Text(AppLocalizations.of(context).profileFormShot)),
                  ],
                  onChanged: (value) => setState(() => unit = value ?? 'bottle'),
                ),
                if (unit == 'bottle' || unit == 'keg')
                  TextField(
                    controller: bottleMlController,
                    decoration: InputDecoration(
                      labelText: unit == 'bottle' ? 'Bottle size (ml)' : 'Keg size (ml)',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                if (unit == 'bottle')
                  DropdownButtonFormField<String?>(
                    initialValue: packType,
                    decoration: const InputDecoration(labelText: 'Pack type (optional)'),
                    items: [
                      DropdownMenuItem(value: null, child: Text(AppLocalizations.of(context).profileFormSingleBottle)),
                      DropdownMenuItem(value: 'crate', child: Text(AppLocalizations.of(context).profileFormCrateOfBottles)),
                      DropdownMenuItem(value: 'carton', child: Text(AppLocalizations.of(context).profileFormCarton)),
                    ],
                    onChanged: (value) => setState(() => packType = value),
                  ),
                TextField(
                  controller: costController,
                  decoration: const InputDecoration(labelText: 'Cost (KES)'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                TextField(
                  controller: priceController,
                  decoration: const InputDecoration(labelText: 'Selling price (KES)'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                if (unit == 'bottle') ...[
                  TextField(
                    controller: halfPriceController,
                    decoration: const InputDecoration(labelText: 'Half price (KES, optional)'),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                  TextField(
                    controller: quarterPriceController,
                    decoration: const InputDecoration(labelText: 'Quarter price (KES, optional)'),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
                TextField(
                  controller: stockController,
                  decoration: const InputDecoration(labelText: 'Starting stock'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).profileFormCancel),
            ),
            FilledButton(
              onPressed: () {
                final cost = double.tryParse(costController.text);
                final price = double.tryParse(priceController.text);
                final stock = double.tryParse(stockController.text);
                final bottleMl = int.tryParse(bottleMlController.text);
                final halfPrice = double.tryParse(halfPriceController.text);
                final quarterPrice = double.tryParse(quarterPriceController.text);

                if (nameController.text.isEmpty ||
                    cost == null ||
                    price == null ||
                    stock == null) {
                  return;
                }

                Navigator.pop(context, {
                  'name': nameController.text,
                  'category': categoryController.text,
                  'unit': unit,
                  'cost': cost,
                  'price': price,
                  'stock': stock,
                  if (bottleMl != null) 'bottle_ml': bottleMl,
                  if (halfPrice != null) 'half_price': halfPrice,
                  if (quarterPrice != null) 'quarter_price': quarterPrice,
                  if (packType != null) 'pack_type': packType,
                });
              },
              child: Text(AppLocalizations.of(context).profileFormSave),
            ),
          ],
        ),
      ),
    );
  }

  static Future<Map<String, dynamic>?> _showFashionForm(
    BuildContext context,
    Product? existing,
  ) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final categoryController = TextEditingController(text: existing?.category ?? 'Fashion');
    final costController = TextEditingController(
        text: existing?.costPrice.asMajor.toStringAsFixed(2) ?? '');
    final priceController = TextEditingController(
        text: existing?.sellPrice.asMajor.toStringAsFixed(2) ?? '');
    final stockController = TextEditingController(
        text: existing?.stockQty.toString() ?? '0');

    bool trackVariants = true; // Fashion always tracks variants
    final variants = <Map<String, dynamic>>[];

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void addVariant() {
            setState(() {
              variants.add({
                'name': '',
                'size': '',
                'colour': '',
                'stock': 0.0,
              });
            });
          }

          void removeVariant(int index) {
            setState(() {
              variants.removeAt(index);
            });
          }

          return AlertDialog(
            title: Text(AppLocalizations.of(context).profileFormAddFashionStyle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Style name'),
                    autofocus: true,
                  ),
                  TextField(
                    controller: categoryController,
                    decoration: const InputDecoration(labelText: 'Collection/Category'),
                  ),
                  TextField(
                    controller: costController,
                    decoration: const InputDecoration(labelText: 'Cost per item (KES)'),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                  TextField(
                    controller: priceController,
                    decoration: const InputDecoration(labelText: 'Selling price per item (KES)'),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  Text(AppLocalizations.of(context).profileFormVariants, style: TextStyle(fontWeight: FontWeight.bold)),
                  ...variants.asMap().entries.map((entry) {
                    final index = entry.key;
                    final variant = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(labelText: 'Variant name'),
                              onChanged: (value) => variant['name'] = value,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(labelText: 'Size'),
                              onChanged: (value) => variant['size'] = value,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(labelText: 'Colour'),
                              onChanged: (value) => variant['colour'] = value,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: () => removeVariant(index),
                          ),
                        ],
                      ),
                    );
                  }),
                  OutlinedButton.icon(
                    onPressed: addVariant,
                    icon: const Icon(Icons.add),
                    label: Text(AppLocalizations.of(context).profileFormAddVariant),
                  ),
                  if (variants.isEmpty)
                    TextField(
                      controller: stockController,
                      decoration: const InputDecoration(labelText: 'Total stock'),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context).profileFormCancel),
              ),
              FilledButton(
                onPressed: () {
                  final cost = double.tryParse(costController.text);
                  final price = double.tryParse(priceController.text);
                  final stock = double.tryParse(stockController.text);

                  if (nameController.text.isEmpty ||
                      cost == null ||
                      price == null) {
                    return;
                  }

                  Navigator.pop(context, {
                    'name': nameController.text,
                    'category': categoryController.text,
                    'track_variants': trackVariants,
                    'cost': cost,
                    'price': price,
                    'stock': variants.isEmpty ? (stock ?? 0) : 0,
                    'variants': variants,
                  });
                },
                child: Text(AppLocalizations.of(context).profileFormSave),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<Map<String, dynamic>?> _showOpenForm(
    BuildContext context,
    Product? existing,
  ) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final priceController = TextEditingController(
        text: existing?.sellPrice.asMajor.toStringAsFixed(2) ?? '');
    final costController = TextEditingController(
        text: existing?.costPrice.asMajor.toStringAsFixed(2) ?? '');
    final stockController = TextEditingController(
        text: existing?.stockQty.toString() ?? '0');
    final unitController = TextEditingController(
        text: existing?.unit.wire ?? 'each');

    bool optionalStock = existing != null;

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(AppLocalizations.of(context).profileFormAddItemOrService),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Item or service name'),
                  autofocus: true,
                ),
                TextField(
                  controller: priceController,
                  decoration: const InputDecoration(labelText: 'Price (KES)'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                CheckboxListTile(
                  title: Text(AppLocalizations.of(context).profileFormTrackStock),
                  value: optionalStock,
                  onChanged: (value) => setState(() => optionalStock = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (optionalStock) ...[
                  TextField(
                    controller: unitController,
                    decoration: const InputDecoration(labelText: 'Unit (e.g. each, kg, litre)'),
                  ),
                  TextField(
                    controller: costController,
                    decoration: const InputDecoration(labelText: 'Cost (KES, optional)'),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                  TextField(
                    controller: stockController,
                    decoration: const InputDecoration(labelText: 'Starting stock (optional)'),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).profileFormCancel),
            ),
            FilledButton(
              onPressed: () {
                final price = double.tryParse(priceController.text);
                final cost = optionalStock ? double.tryParse(costController.text) : 0;
                final stock = optionalStock ? double.tryParse(stockController.text) : 0;

                if (nameController.text.isEmpty || price == null) {
                  return;
                }

                Navigator.pop(context, {
                  'name': nameController.text,
                  'category': 'Optional stock',
                  'price': price,
                  'cost': cost ?? 0,
                  'stock': stock ?? 0,
                  'unit': optionalStock ? (unitController.text.trim().isEmpty ? 'each' : unitController.text.trim()) : 'each',
                  'optional_stock': optionalStock,
                });
              },
              child: Text(AppLocalizations.of(context).profileFormSave),
            ),
          ],
        ),
      ),
    );
  }
}