import 'package:flutter/material.dart';

import 'shop_profile.dart';
import '../models/models.dart';

/// Profile-specific product creation flows.
/// 
/// Each profile gets a tailored add-product flow:
/// - Drinks: bottle/shot/crate
/// - Duka: counted/pack/repack
/// - Fashion: style/size/colour
/// - Open: money-first optional stock
class ProfileProductForms {
  const ProfileProductForms();

  /// Creates a product form tailored to the profile.
  /// 
  /// Returns a map of field values keyed by field name.
  static Future<Map<String, dynamic>?> showForm({
    required BuildContext context,
    required ShopProfile profile,
    Product? existingProduct,
  }) async {
    return switch (profile) {
      ShopProfile.drinks => _showDrinksForm(context, existingProduct),
      ShopProfile.duka => _showDukaForm(context, existingProduct),
      ShopProfile.fashion => _showFashionForm(context, existingProduct),
      ShopProfile.open => _showOpenForm(context, existingProduct),
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
          title: const Text('Add drink'),
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
                  items: const [
                    DropdownMenuItem(value: 'bottle', child: Text('Bottle')),
                    DropdownMenuItem(value: 'crate', child: Text('Crate')),
                    DropdownMenuItem(value: 'keg', child: Text('Keg')),
                    DropdownMenuItem(value: 'shot', child: Text('Shot')),
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
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Single bottle')),
                      DropdownMenuItem(value: 'crate', child: Text('Crate of bottles')),
                      DropdownMenuItem(value: 'carton', child: Text('Carton')),
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
              child: const Text('Cancel'),
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<Map<String, dynamic>?> _showDukaForm(
    BuildContext context,
    Product? existing,
  ) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final categoryController = TextEditingController(text: existing?.category ?? 'General');
    final costController = TextEditingController(
        text: existing?.costPrice.asMajor.toStringAsFixed(2) ?? '');
    final priceController = TextEditingController(
        text: existing?.sellPrice.asMajor.toStringAsFixed(2) ?? '');
    final stockController = TextEditingController(
        text: existing?.stockQty.toString() ?? '0');
    final reorderController = TextEditingController(
        text: existing?.reorderLevel.toString() ?? '5');

    String unit = existing?.unit.wire ?? 'each';
    bool trackVariants = existing?.trackVariants ?? false;

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add product'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Product name'),
                  autofocus: true,
                ),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: const [
                    DropdownMenuItem(value: 'each', child: Text('Each')),
                    DropdownMenuItem(value: 'kg', child: Text('Kilogram')),
                    DropdownMenuItem(value: 'litre', child: Text('Litre')),
                    DropdownMenuItem(value: 'pack', child: Text('Pack')),
                    DropdownMenuItem(value: 'carton', child: Text('Carton')),
                  ],
                  onChanged: (value) => setState(() => unit = value ?? 'each'),
                ),
                CheckboxListTile(
                  title: const Text('Track variants (sizes/colours)'),
                  value: trackVariants,
                  onChanged: (value) => setState(() => trackVariants = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
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
                TextField(
                  controller: stockController,
                  decoration: const InputDecoration(labelText: 'Starting stock'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                TextField(
                  controller: reorderController,
                  decoration: const InputDecoration(labelText: 'Reorder level'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final cost = double.tryParse(costController.text);
                final price = double.tryParse(priceController.text);
                final stock = double.tryParse(stockController.text);
                final reorder = int.tryParse(reorderController.text);

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
                  'track_variants': trackVariants,
                  'cost': cost,
                  'price': price,
                  'stock': stock,
                  'reorder_level': reorder ?? 5,
                });
              },
              child: const Text('Save'),
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
            title: const Text('Add fashion style'),
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
                  const Text('Variants', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    label: const Text('Add variant'),
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
                child: const Text('Cancel'),
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
                child: const Text('Save'),
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

    bool optionalStock = existing != null;

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add item or service'),
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
                  title: const Text('Track stock'),
                  value: optionalStock,
                  onChanged: (value) => setState(() => optionalStock = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (optionalStock) ...[
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
              child: const Text('Cancel'),
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
                  'optional_stock': optionalStock,
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}