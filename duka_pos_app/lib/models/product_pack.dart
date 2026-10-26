import '../utils/money.dart';

/// A barcodeable selling/receiving pack for one product (for example, a case
/// of 24 bottles). Stock remains in base units; the pack only changes how a
/// scan or receipt quantity is converted.
class ProductPack {
  const ProductPack({
    this.id,
    required this.uuid,
    required this.productId,
    this.variantId,
    required this.name,
    required this.barcode,
    required this.unitsPerPack,
    required this.unitCost,
    this.sellPrice,
    this.active = true,
  });

  final int? id;
  final String uuid;
  final int productId;
  final int? variantId;
  final String name;
  final String barcode;
  final double unitsPerPack;
  final Money unitCost;
  final Money? sellPrice;
  final bool active;

  factory ProductPack.fromMap(Map<String, dynamic> row) => ProductPack(
        id: row['id'] as int?,
        uuid: row['uuid'] as String,
        productId: row['product_id'] as int,
        variantId: (row['variant_id'] as num?)?.toInt(),
        name: row['name'] as String,
        barcode: row['barcode'] as String,
        unitsPerPack: (row['units_per_pack'] as num).toDouble(),
        unitCost: Money.fromMinor((row['unit_cost_minor'] as num).toInt()),
        sellPrice: (row['sell_price_minor'] as num?) == null
            ? null
            : Money.fromMinor((row['sell_price_minor'] as num).toInt()),
        active: (row['active'] as num? ?? 1) == 1,
      );
}
