import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/utils/units.dart';

void main() {
  test('product identity metadata round-trips without changing POS fields', () {
    final product = Product(
      id: 7,
      name: 'Work gloves',
      category: 'Hardware',
      costPrice: Money.fromMinor(250),
      sellPrice: Money.fromMinor(500),
      stockQty: 4,
      reorderLevel: 1,
      unit: ProductUnit.each,
      updatedAt: '2026-11-19T10:00:00.000Z',
      productUuid: 'c86fcd3c-9081-4860-a538-e30ad5b9613c',
      itemKind: 'good',
      gpcCode: '10000001',
      gpcVersion: '2026-05',
      gpcMappingStatus: 'mapped',
      merchantSku: 'WG-01',
      brandLabelLocal: 'Shop label',
      unitMappingStatus: 'not_applicable',
      identityProvenance: 'owner_confirmed',
    );

    final restored = Product.fromMap(product.toMap());

    expect(restored.productUuid, product.productUuid);
    expect(restored.itemKind, 'good');
    expect(restored.gpcCode, '10000001');
    expect(restored.gpcVersion, '2026-05');
    expect(restored.merchantSku, 'WG-01');
    expect(restored.brandLabelLocal, 'Shop label');
    expect(restored.name, product.name);
    expect(restored.sellPrice, product.sellPrice);
  });

  test('services and fees are not treated as stockout items', () {
    Product item(String kind) => Product(
          name: 'Line',
          category: 'General',
          costPrice: Money.zero,
          sellPrice: Money.fromMinor(1),
          stockQty: 0,
          reorderLevel: 0,
          itemKind: kind,
          updatedAt: '',
        );
    expect(item('service').isOutOfStock, isFalse);
    expect(item('fee').isOutOfStock, isFalse);
    expect(item('service').isLow, isFalse);
    expect(item('fee').isLow, isFalse);
    expect(item('good').isOutOfStock, isTrue);
  });
}
