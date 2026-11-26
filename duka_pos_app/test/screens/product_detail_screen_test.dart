import 'package:duka_pos/l10n/generated/app_localizations.dart';
import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/product_detail_screen.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

Product _product({
  String name = 'Fresh milk 500 ml',
  double stockQty = 16,
  double reservedQty = 3,
  bool trackStock = true,
}) =>
    Product(
      name: name,
      category: 'Dairy',
      costPrice: Money.fromMinor(12000),
      sellPrice: Money.fromMinor(16000),
      stockQty: stockQty,
      reservedQty: reservedQty,
      reorderLevel: 4,
      updatedAt: '2026-03-01T10:00:00.000',
      trackStock: trackStock,
      trackExpiry: true,
      merchantSku: 'SKU-418',
      brandLabelLocal: 'Farm Fresh',
    );

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await loadAppFonts();
    l10n = await loadL10n();
  });

  testWidgets('shows product identity, available stock and inventory details',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: ProductDetailScreen(product: _product()),
    );

    expect(find.text('Fresh milk 500 ml'), findsOneWidget);
    expect(find.text(l10n.inventoryAvailableStock), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    expect(find.text(l10n.inventoryProductInformation), findsOneWidget);
    expect(find.text('SKU-418'), findsOneWidget);
    expect(find.text('Farm Fresh'), findsOneWidget);
    expect(find.text('3 each'), findsOneWidget);
    expect(find.text(l10n.inventoryTracked), findsOneWidget);
    expect(find.text(l10n.inventoryNoMovement), findsOneWidget);

    final OutlinedButton salesButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, l10n.viewSales),
    );
    expect(salesButton.onPressed, isNotNull);
    tester.expectNoOverflow('product details');
  });

  testWidgets('does not present untracked stock as available inventory',
      (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: ProductDetailScreen(
        product: _product(
          name: 'Delivery fee',
          stockQty: 0,
          reservedQty: 0,
          trackStock: false,
        ),
      ),
    );

    expect(find.text(l10n.inventoryStockNotTracked), findsWidgets);
    expect(find.text(l10n.inventoryReorderLevel), findsNothing);
    expect(find.text('0 each'), findsNothing);
  });

  for (final Device device in <Device>[Device.compact, Device.small]) {
    for (final double scale in <double>[1.0, 2.0]) {
      for (final Brightness brightness in <Brightness>[
        Brightness.light,
        Brightness.dark,
      ]) {
        final String where = '${device.name} x$scale $brightness';
        testWidgets('fits $where', (tester) async {
          tester.useDevice(device);
          await tester.pumpApp(
            home: ProductDetailScreen(
              product: _product(
                name:
                    'Extra fresh whole milk in a large bottle with a very long product name',
              ),
            ),
            textScaler: TextScaler.linear(scale),
            brightness: brightness,
          );
          tester.expectNoOverflow('product detail $where');
        });
      }
    }
  }
}
