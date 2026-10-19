// The till page: the layout, the tiles, and the two ways they used to break.
//
// WHAT THESE TESTS ARE FOR
//
// Two shipped bugs, one cause each.
//
// 1. THE CRASH. The page's pane layout divided a height, and it was a
//    non-flexible child of a Column — and a Column hands its non-flexible
//    children an UNBOUNDED height. In a release build the unbounded height
//    reached the catalogue's grid, the grid's scroll extent became infinite,
//    and the sliver's index arithmetic threw "Unsupported operation: Infinity
//    or NaN to Int" the moment the till opened on a phone. The test that
//    matters is the one that lays the page out in a BOUNDED box: an
//    unbounded one is the bug, and the assertion in [SellPaneLayout] says so.
//
// 2. THE CLIPPED TILE. The catalogue grid fixed a cell's shape with a ratio
//    of its width, and a ratio is a guess about how much text a cell holds.
//    On a 360dp phone with photographs on the products, the guess was about
//    35dp short, and the name — the one thing in a tile allowed to be cut
//    short — was squeezed to nothing while the rest of the tile overflowed.
//
// The matrix is the one the design system uses: the phone widths, the text
// scales, and both themes. A tile that survives a phone at 200% text is a
// tile that survives a shop.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/widgets/product_tile.dart';
import 'package:duka_pos/widgets/sell_page.dart';

import '../support/harness.dart';

/// The text scales a real phone can be set to.
///
/// 1.3 is the Android "large" step. 2.0 is the accessibility step, and it is
/// where a fixed height stops being a height.
const List<double> _textScales = <double>[1.0, 1.3, 2.0];

Product _product({
  String name = 'Kenyatta bread',
  double stock = 12,
  String? imagePath,
  double price = 60,
}) {
  return Product(
    name: name,
    category: 'Bakery',
    costPrice: Money.fromMajor(price / 2),
    sellPrice: Money.fromMajor(price),
    stockQty: stock,
    reorderLevel: 5,
    updatedAt: '2026-01-01T00:00:00.000Z',
    imagePath: imagePath,
  );
}

ProductTileData _tile(Product product) {
  return ProductTileData(
    product: product,
    inCart: 0,
    sellsAsVariants: false,
    variantCount: 0,
    cheapestPrice: null,
    canTap: product.stockQty > 0,
  );
}

/// The till page, as the screen builds it: a brand strip and two panes.
///
/// The `Expanded` around the pane layout is the fix, and it is part of the
/// page rather than of the test: a Column hands a non-flexible child an
/// unbounded height, and the pane layout divides a height.
Widget _page({
  required List<ProductTileData> items,
  bool compact = true,
  void Function(Product product)? onProduct,
}) {
  return Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('SimpleSales'),
          ),
          Expanded(
            child: SellPaneLayout(
              compact: compact,
              catalogue: SellCataloguePane(
                controller: TextEditingController(),
                focusNode: FocusNode(),
                query: '',
                onQueryChanged: (String _) {},
                onClearQuery: () {},
                onScan: () {},
                scanning: false,
                loading: false,
                items: items,
                onProduct: onProduct ?? (Product _) {},
              ),
              cart: SellCartPane(
                lines: const <SellCartLine>[],
                itemCountLabel: '0 items',
                totalLabel: 'KSh 0.00',
                emptyHint: 'Tap products to add',
                offlineLabel: 'Record offline payment',
                mpesaLabel: 'M-Pesa',
                onOffline: () {},
                onMpesa: () {},
                processing: false,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  // The real typeface, not the test font.
  //
  // Without this, every glyph is an Ahem square one em wide — so a price that
  // is 8 characters wide is measured at 8 ems, and a layout that would pass on
  // a phone fails here for a reason no phone has. A test that cannot tell the
  // difference between Ahem and Plus Jakarta Sans cannot tell the difference
  // between a layout that fits and one that does not.
  setUpAll(loadAppFonts);

  group('the till page lays out without overflowing', () {
    for (final Device device in Device.all) {
      for (final double scale in _textScales) {
        for (final Brightness brightness in <Brightness>[
          Brightness.light,
          Brightness.dark
        ]) {
          testWidgets(
            '${device.name} at ${scale}x text, $brightness, with photographs',
            (WidgetTester tester) async {
              tester.useDevice(device);

              await tester.pumpApp(
                home: _page(
                  items: <ProductTileData>[
                    _tile(_product(imagePath: 'photos/bread.png')),
                    _tile(
                      _product(
                        name:
                            'A product with a name the length of a sentence that a shopkeeper would actually type',
                        stock: 0.4,
                        price: 1250,
                      ),
                    ),
                    _tile(_product(name: 'Milk', stock: 3, price: 85)),
                  ],
                ),
                brightness: brightness,
                textScaler: TextScaler.linear(scale),
              );
              await tester.pump();

              tester.expectNoOverflow(
                'the till page on ${device.name} at ${scale}x in $brightness',
              );
            },
          );
        }
      }
    }
  });

  group('the till is usable on a phone', () {
    // The bug these two are about is not a crash — it is a page that PAINTS
    // NOTHING. The pane layout was a non-flexible child of a Column, so it
    // was given an unbounded height, the grid's viewport inherited it, the
    // grid's scroll extent became infinite, and the sliver's index
    // arithmetic threw while the frame was painting. The frame that would
    // have drawn the products and the cart is the frame that died.
    //
    // "No exception" is therefore not the proof. The proof is that the
    // products and the cart are ON SCREEN, and that a tap lands on one.

    testWidgets('the products are on screen, and a tap lands on one',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      final List<Product> tapped = <Product>[];
      await tester.pumpApp(
        home: _page(
          items: <ProductTileData>[_tile(_product())],
          onProduct: tapped.add,
        ),
      );
      await tester.pump();

      final Finder tile = find.byType(ProductTile);
      expect(tile, findsOneWidget);

      // On screen: the tile's box is inside the window, not laid out at some
      // infinite coordinate above it.
      final Rect rect = tester.getRect(tile);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(800));
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));

      // And it is what a finger would land on: `tester.tap` throws when the
      // hit test misses the widget it was aimed at, so a successful tap IS
      // the proof that the tile is on screen and reachable.
      await tester.tap(tile);
      expect(tapped, hasLength(1),
          reason: 'a product that cannot be tapped cannot be sold');
    });

    testWidgets('the cart is on screen, with the money and the charge button',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: _page(items: <ProductTileData>[_tile(_product())]),
      );
      await tester.pump();

      // The total, and the way to charge it. Both on screen — inside the
      // window, not laid out somewhere the eye cannot reach.
      final Rect total = tester.getRect(find.text('KSh 0.00'));
      expect(total.top, greaterThanOrEqualTo(0));
      expect(total.bottom, lessThanOrEqualTo(800));

      final Finder charge =
          find.widgetWithText(ElevatedButton, 'Record offline payment');
      final Rect chargeRect = tester.getRect(charge);
      expect(chargeRect.top, greaterThanOrEqualTo(0));
      expect(chargeRect.bottom, lessThanOrEqualTo(800));

      // And a tap lands on the charge button — a cart the cashier cannot
      // charge from is a cart that cannot be sold.
      await tester.tap(charge);
      expect(tester.takeException(), isNull);
    });

    test('the pane layout refuses a box with no height', () {
      // The shape that caused the crash: the pane layout as a non-flexible
      // child of a Column, which is an unbounded height. The layout says so
      // out loud now, instead of letting it arrive three frames later as an
      // arithmetic error about infinity.
      expect(
        SellPaneLayout.canDivide(
          const BoxConstraints(maxHeight: double.infinity),
        ),
        isFalse,
      );
      expect(
        SellPaneLayout.canDivide(const BoxConstraints(maxHeight: 600)),
        isTrue,
      );
    });
  });

  group('a tile is never clipped', () {
    testWidgets('the grid gives every tile the room its text needs',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: Scaffold(
          body: ProductTileGrid(
            items: <ProductTileData>[
              _tile(_product(imagePath: 'photos/bread.png')),
            ],
            onTap: (Product _) {},
          ),
        ),
      );
      await tester.pump();

      tester.expectNoOverflow('the catalogue grid');

      // The name is on screen, and it is not squeezed to nothing — which is
      // what an over-tight cell did to it.
      final Finder name = find.text('Kenyatta bread');
      expect(name, findsOneWidget);
      expect(tester.getSize(name).height, greaterThan(0));
    });

    testWidgets('a long name and a long price survive a 360dp phone',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: Scaffold(
          body: ProductTileGrid(
            items: <ProductTileData>[
              _tile(
                _product(
                  name: 'Special blend arabica coffee beans from the highlands '
                      'of Kirinyiga washed and sun dried',
                  price: 125000,
                  imagePath: 'photos/coffee.png',
                ),
              ),
            ],
            onTap: (Product _) {},
          ),
        ),
      );
      await tester.pump();

      tester.expectNoOverflow('a long name in the catalogue grid');
    });
  });

  group('the cart never truncates money', () {
    testWidgets('a large total wraps instead of being cut',
        (WidgetTester tester) async {
      tester.useDevice(Device.compact);

      await tester.pumpApp(
        home: Scaffold(
          body: SellCartPane(
            lines: <SellCartLine>[
              SellCartLine(
                title:
                    'A product with a very long name that a shopkeeper typed',
                subtitle: '500ml · KSh 1,240.00',
                quantity: '1',
                decreaseLabel: 'Remove one',
                increaseLabel: 'Add one',
                removeLabel: 'Remove',
                onDecrease: () {},
                onIncrease: () {},
                onRemove: () {},
              ),
            ],
            itemCountLabel: '1 item',
            totalLabel: 'KSh 1,240,000.00',
            emptyHint: 'Tap products to add',
            offlineLabel: 'Offline payment',
            mpesaLabel: 'M-Pesa',
            onOffline: () {},
            onMpesa: () {},
            processing: false,
          ),
        ),
        textScaler: TextScaler.linear(2.0),
      );
      await tester.pump();

      tester.expectNoOverflow('the cart at 2x text');

      // The whole amount is on screen. A price that does not fit is a layout
      // bug to fix with a taller box, not a number to cut.
      expect(find.text('KSh 1,240,000.00'), findsOneWidget);
      expect(find.text('500ml · KSh 1,240.00'), findsOneWidget);
    });
  });

  group('a stock count is read, not rounded', () {
    test('a whole number is whole', () {
      expect(ProductTileData.stockText(12), '12');
      expect(ProductTileData.stockText(0), '0');
    });

    test('a fraction keeps its decimal', () {
      // 0.4 read as "0" said the shelf was empty on a tile that was still
      // tappable. 2.5 read as "3" was a bottle charged for that was never
      // counted.
      expect(ProductTileData.stockText(0.4), '0.4');
      expect(ProductTileData.stockText(2.5), '2.5');
      expect(ProductTileData.stockText(0.5), '0.5');
    });

    testWidgets('the tile says 0.4, not 0', (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: Scaffold(body: ProductTile(data: _tile(_product(stock: 0.4)))),
      );
      await tester.pump();

      expect(find.textContaining('0.4'), findsOneWidget);
      expect(find.textContaining('0 in stock'), findsNothing);
    });
  });

  group('a tile is one thing to a screen reader', () {
    testWidgets('the tile announces the product, the price and the stock',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: Scaffold(body: ProductTile(data: _tile(_product(stock: 12)))),
      );
      await tester.pump();

      final SemanticsNode node = tester.getSemantics(find.byType(ProductTile));
      expect(node.label, 'Kenyatta bread, KSh 60, 12 in stock');
      expect(node.hint, 'Adds it to the cart');
      handle.dispose();
    });
  });
}
