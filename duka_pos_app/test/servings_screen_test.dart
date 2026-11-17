import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/servings_screen.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rows = <Serving>[
    Serving(
      productId: 1,
      productName: 'Navy Gin',
      capacity: 30,
      unit: 'ml',
      price: Money.fromMajor(80),
      label: 'Single',
      updatedAt: '2026-01-01T00:00:00Z',
    ),
    Serving(
      productId: 2,
      productName: 'Orange Juice',
      capacity: 250,
      unit: 'ml',
      price: Money.fromMajor(120),
      label: 'Glass',
      updatedAt: '2026-01-01T00:00:00Z',
    ),
    Serving(
      productId: 1,
      productName: 'Navy Gin',
      capacity: 60,
      unit: 'ml',
      price: Money.fromMajor(140),
      label: 'Double',
      active: false,
      updatedAt: '2026-01-01T00:00:00Z',
    ),
  ];

  test('search matches serving labels and parent products', () {
    expect(
      filterServings(rows, query: 'navy')
          .map((Serving serving) => serving.label),
      <String>['Single'],
    );
    expect(
      filterServings(rows, query: 'glass')
          .map((Serving serving) => serving.productName),
      <String>['Orange Juice'],
    );
  });

  test('search respects product and unit filters and excludes inactive rows',
      () {
    final result = filterServings(
      rows,
      productId: 1,
      unit: 'ml',
      query: 'single',
    );
    expect(result.map((Serving serving) => serving.label), <String>['Single']);
    expect(filterServings(rows, query: 'double'), isEmpty);
  });

  test(
      'editor preserves a declared remote unit and defaults new servings to ml',
      () {
    expect(servingEditorUnit(rows.first), 'ml');
    expect(
      servingEditorUnit(
        Serving(
          productId: 3,
          productName: 'Syrup',
          capacity: 0.5,
          unit: 'litre',
          price: Money.fromMajor(100),
          label: 'Half litre',
          updatedAt: '2026-01-01T00:00:00Z',
        ),
      ),
      'litre',
    );
    expect(servingEditorUnit(null), 'ml');
  });

  test('serving capacity presentation preserves the declared unit', () {
    expect(formatServingCapacity(30, 'ml'), '30 ml');
    expect(formatServingCapacity(0.5, 'litre'), '0.5 L');
    expect(formatServingCapacity(2, 'kilogram'), '2 kg');
  });
}
