// Reads and writes the things a variant-aware screen needs that the models and
// the database helper do not currently expose.
//
// Three gaps are papered over here, each because a screen that cannot see the
// truth cannot act on it:
//
//   1. `Product.fromMap` does not populate `unit` or `trackVariants`, so every
//      product read back from SQLite arrives as "each, not sold as variants"
//      no matter what the row says. [VariantCatalogue.load] therefore reads the
//      two columns directly. When `Product.fromMap` learns to read them, this
//      file keeps working — it only ever reads the row.
//   2. `product_barcodes.variant_id` is what makes a code resolve to a variant
//      rather than to the parent, but `ProductBarcode` has no field for it and
//      `addBarcode` has no parameter for it. [codesForProduct] and
//      [addVariantCode] reach the column so the editor can show which is which.
//   3. `recordSale` checks and decrements `products.stock_qty`, so a variant's
//      own count is never touched by a sale. [deductVariantStock] and
//      [adjustVariantStock] keep it honest, and [writeAggregateStock] keeps the
//      parent's row — which the ledger does check — equal to the sum of the
//      variants.
//
// Every one of these belongs in the model or the database helper. They live in
// a widget-adjacent file only because those two are being written by someone
// else right now; the SQL here is deliberately narrow, and each workaround
// says what replaces it.

import 'package:flutter/foundation.dart';

import '../l10n/generated/app_localizations.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import '../utils/units.dart';

/// One barcode a product answers to, and *what* it answers to.
///
/// A product carries codes at two levels and they are not interchangeable: a
/// product-level code means "this whole product, whatever size", while a
/// variant-level code means "this one variant" and resolves to the variant's
/// price and stock. The editor shows both, labelled, because a code with no
/// label is a code the owner cannot tell apart from the other one.
@immutable
class ProductCode {
  const ProductCode({
    required this.barcode,
    this.kind = BarcodeKind.supplier,
    this.variantId,
    this.variantName = '',
  });

  final String barcode;
  final String kind;

  /// Null for a product-level code.
  final int? variantId;

  /// The variant's name as stored, denormalised here only so the list can label
  /// a code without a second query per row.
  final String variantName;

  bool get isVariantLevel => variantId != null;

  /// "Dark 500 ml" for a variant-level code, "All sizes" for a product-level
  /// one. Spelled out rather than an icon, because the distinction the owner is
  /// looking for is which of their own words the code means.
  /// Takes the catalogue in, because a getter cannot reach one: this is a value
  /// type built in a `rawQuery` loop, far above any `Localizations` ancestor.
  String scopeLabel(AppLocalizations l10n) {
    final name = variantName.trim();
    if (!isVariantLevel) return l10n.variantAllSizesLabel;
    return name.isEmpty ? l10n.variantOneVariantLabel : name;
  }
}

/// Which products are sold as variants, and what those variants are.
///
/// Held as a snapshot rather than queried per tile or per cart line: the till
/// asks the same two questions once per product, repeatedly, and a sheet that
/// awaits a query per tile is a sheet that stutters.
@immutable
class VariantCatalogue {
  const VariantCatalogue({
    this.trackingProductIds = const {},
    this.variantsByProduct = const {},
    this.variantsById = const {},
  });

  static const VariantCatalogue empty = VariantCatalogue();

  /// Products whose `track_variants` is set — "sold as variants", whether or not
  /// any variant has been added yet.
  final Set<int> trackingProductIds;

  /// Active variants per product, in the owner's order.
  final Map<int, List<ProductVariant>> variantsByProduct;

  final Map<int, ProductVariant> variantsById;

  /// Whether the owner said this product is sold as variants.
  bool tracks(Product product) =>
      product.id != null && trackingProductIds.contains(product.id);

  List<ProductVariant> of(Product product) => product.id == null
      ? const <ProductVariant>[]
      : variantsByProduct[product.id] ?? const <ProductVariant>[];

  ProductVariant? byId(int? id) => id == null ? null : variantsById[id];

  /// Whether the till must offer variants instead of portions.
  ///
  /// True when the flag is set *or* when variants exist, because a product
  /// whose variants exist but whose flag was never ticked is still a product
  /// the cashier cannot sell as a whole bottle. Treating those two states
  /// differently is how "Dark" and "Regular" quietly merge back into the
  /// parent's price at the till.
  bool sellsAsVariants(Product product) =>
      tracks(product) || of(product).isNotEmpty;

  /// The cheapest thing this product can be sold as, for "from KSh 60" on a
  /// tile that no longer has a single price.
  ProductVariant? cheapestVariant(Product product) {
    final variants = of(product);
    if (variants.isEmpty) return null;
    return variants.reduce((a, b) => a.sellPrice <= b.sellPrice ? a : b);
  }

  /// Reads the whole variant picture in two queries.
  static Future<VariantCatalogue> load() async {
    final db = DatabaseHelper.instance;
    final variants = await db.getAllVariants();
    final byProduct = <int, List<ProductVariant>>{};
    final byId = <int, ProductVariant>{};
    for (final variant in variants) {
      if (!variant.active) continue;
      byId[variant.id!] = variant;
      byProduct.putIfAbsent(variant.productId, () => []).add(variant);
    }
    // `getAllVariants` orders by product, position, id — the order the owner
    // arranged them in — and grouping preserves it.
    return VariantCatalogue(
      trackingProductIds: await loadTrackingProductIds(),
      variantsByProduct: byProduct,
      variantsById: byId,
    );
  }

  /// Ids of every product flagged as sold as variants.
  ///
  /// Named apart from the field it fills: a static and an instance member of the
  /// same name is a compile error, and the field is the one read at the till.
  static Future<Set<int>> loadTrackingProductIds() async {
    final rows = await (await DatabaseHelper.instance.database)
        .rawQuery('SELECT id FROM products WHERE track_variants = 1');
    return rows.map((row) => row['id'] as int).toSet();
  }

  /// `products.unit` and `products.track_variants`, read straight from the row.
  ///
  /// Needed because [Product.fromMap] ignores both columns (see the file
  /// header): without this, opening a product in the editor would show "each,
  /// not sold as variants" and saving it would write that back.
  static Future<({ProductUnit unit, bool trackVariants})> productFlags(
      int productId) async {
    final rows = await (await DatabaseHelper.instance.database).query(
      'products',
      columns: ['unit', 'track_variants'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return (unit: ProductUnit.each, trackVariants: false);
    }
    final row = rows.first;
    return (
      unit: ProductUnit.parse(row['unit'] as String?),
      trackVariants: ((row['track_variants'] as num?)?.toInt() ?? 0) == 1,
    );
  }

  /// Every code held by a product, each labelled with the level it resolves at.
  static Future<List<ProductCode>> codesForProduct(int productId) async {
    final rows = await (await DatabaseHelper.instance.database).rawQuery(
      '''SELECT b.barcode, b.kind, b.variant_id, v.name AS variant_name
           FROM product_barcodes b
           LEFT JOIN product_variants v ON v.id = b.variant_id
          WHERE b.product_id = ?
          ORDER BY b.barcode''',
      [productId],
    );
    return rows
        .map((row) => ProductCode(
              barcode: row['barcode'] as String,
              kind: (row['kind'] as String?) ?? BarcodeKind.supplier,
              variantId: row['variant_id'] as int?,
              variantName: (row['variant_name'] as String?) ?? '',
            ))
        .toList();
  }

  /// Attaches a barcode to one variant.
  ///
  /// Attaches [barcode] to one variant rather than to its parent product.
  ///
  /// Thin delegation to `DatabaseHelper.addBarcode`, which now takes a
  /// `variantId`. This used to be raw SQL here, written because `addBarcode` had
  /// no way to reach the column — a second, independent write path into
  /// `product_barcodes` from a widget file, which is exactly how the two drift
  /// apart on a later change. Returns false when the code is already taken by
  /// any product or variant, matching "refuse rather than re-point".
  static Future<bool> addVariantCode({
    required int productId,
    required int variantId,
    required String barcode,
    String kind = BarcodeKind.supplier,
  }) =>
      DatabaseHelper.instance.addBarcode(
        productId: productId,
        barcode: barcode,
        kind: kind,
        variantId: variantId,
      );

  /// The same variant with a different stock count.
  ///
  /// [ProductVariant] has no `copyWith`, and a variant has enough fields that
  /// spelling them out at each call site is how one of them gets dropped.
  static ProductVariant withStock(ProductVariant variant, double stockQty) =>
      ProductVariant(
        id: variant.id,
        productId: variant.productId,
        name: variant.name,
        sku: variant.sku,
        unit: variant.unit,
        sizeMl: variant.sizeMl,
        sellPrice: variant.sellPrice,
        costPrice: variant.costPrice,
        stockQty: stockQty,
        reorderLevel: variant.reorderLevel,
        position: variant.position,
        active: variant.active,
      );

  /// Applies a signed correction to one variant's stock.
  ///
  /// Refuses a correction that would take stock below zero, because a negative
  /// count is a stock-take problem nobody can reconcile later.
  static Future<void> adjustVariantStock(int variantId, double delta) async {
    final db = DatabaseHelper.instance;
    final variant = await db.getVariantById(variantId);
    if (variant == null) throw StateError('Variant not found');
    final next = variant.stockQty + delta;
    if (next < 0) throw StateError('Stock cannot go below zero');
    await db.upsertVariant(withStock(variant, next));
    await _refreshAggregateIfTracked(variant.productId);
  }

  /// Takes [qty] off a variant's stock after its sale is committed.
  ///
  /// Clamped at zero rather than refused: the money is already taken, and a
  /// clamped count that needs a stock take beats a till that refuses to hand
  /// over change.
  static Future<void> deductVariantStock(int variantId, double qty) async {
    if (qty <= 0) return;
    final db = DatabaseHelper.instance;
    final variant = await db.getVariantById(variantId);
    if (variant == null) return;
    final next = variant.stockQty - qty;
    await db.upsertVariant(withStock(variant, next < 0 ? 0 : next));
    await _refreshAggregateIfTracked(variant.productId);
  }

  /// Writes the sum of a product's active variants into its own `stock_qty`.
  ///
  /// For a product sold as variants, the parent row is an aggregate rather than
  /// an independent count: it is what the dashboard shows, and it is what
  /// `recordSale` checks and decrements. Left alone it drifts in both
  /// directions — the till decrements it on every sale while the variants it is
  /// supposed to summarise never move — and a parent that has drifted to zero
  /// refuses every sale of a product that is plainly in stock.
  static Future<void> writeAggregateStock(int productId) async {
    final variants = await DatabaseHelper.instance.getVariants(productId);
    final total = variants.fold<double>(0, (sum, v) => sum + v.stockQty);
    await (await DatabaseHelper.instance.database).rawUpdate(
      'UPDATE products SET stock_qty = ?, updated_at = ? WHERE id = ?',
      [total, DateTime.now().toIso8601String(), productId],
    );
  }

  /// Rewrites the aggregate only when the product is actually sold as variants.
  ///
  /// A product that does not track variants has an authoritative count of its
  /// own; overwriting it with a sum of nothing would be a silent deletion.
  static Future<void> _refreshAggregateIfTracked(int productId) async {
    final flags = await productFlags(productId);
    if (flags.trackVariants) await writeAggregateStock(productId);
  }
}

/// The name a variant is sold and printed under.
///
/// `SaleItem` lives in a file this feature may not edit and has no variant
/// field, so the variant is folded into the name where the ledger line is
/// built (see sell_screen). Doing it there rather than in the model is also
/// what keeps the receipt honest later: the line already reads "Kenyana Beer ·
/// Dark" after the owner renames or deletes the variant, which is the only
/// thing a receipt the customer was handed can do.
///
/// The size is dropped first when the combined label would not fit the paper.
/// `ReceiptBuilder` truncates a label from the *end* to leave room for the
/// figure, so a long name plus a size would lose the size — the part that says
/// which of two same-priced variants this is.
String foldedVariantName(Product product, ProductVariant variant) {
  final withSize = '${product.name} · ${variant.label}'.trim();
  if (withSize.length <= kReceiptLabelRoom) return withSize;
  return '${product.name} · ${variant.name}'.trim();
}

/// Characters a label may use on a 58mm receipt before the figure is laid out:
/// the 32-column paper, less a money figure and the gap between them.
///
/// Mirrors `ReceiptBuilder`'s own budget rather than importing it, because the
/// builder is a printer concern and this is a naming one — the two must agree,
/// and a number written next to its reason changes for a reason.
const int kReceiptLabelRoom = 24;
