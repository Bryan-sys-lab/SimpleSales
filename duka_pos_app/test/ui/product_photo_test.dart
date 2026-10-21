// A product's photograph, and the three things that were wrong with it.
//
//  * The path was resolved on EVERY BUILD. A `FutureBuilder` handed a new
//    future starts over, so the snapshot went back to "waiting" and the "no
//    photograph" placeholder flashed in and out on every rebuild of the till
//    grid — which rebuilds on every keystroke in the search box and on every
//    cart tap. A shop full of products with pictures, and the pictures blink.
//
//  * The decode asked for twice the drawn width, whatever the screen's pixel
//    ratio was. Soft on a 3x phone, wasteful on a 2x one.
//
//  * A product with no photograph was drawn with the "image not supported"
//    glyph — a picture of something going wrong — on a tile that is simply a
//    product that has not been photographed yet.
//
// The resolver is INJECTED, because resolving a path means asking the
// platform where the app's documents folder is, and a widget whose only path
// to a photograph is the platform cannot be pumped in a test.

import 'dart:io';

import 'package:duka_pos/ui/components/product_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late Directory temp;
  late File photo;

  // The file is written HERE, not inside a test: a `testWidgets` body runs in
  // a fake-async zone, and real file I/O inside one never completes — the
  // test waits forever for a write that the clock will not advance.
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('duka_photo_test');
    photo = File('${temp.path}/photo.png');
    await photo.writeAsBytes(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  testWidgets('the path is resolved ONCE, however often the tile rebuilds',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    int resolutions = 0;
    Widget tile() => Scaffold(
          body: ProductPhoto(
            imagePath: 'product_photos/1.jpg',
            size: 56,
            resolve: (String path) async {
              resolutions++;
              return photo.path;
            },
          ),
        );

    await tester.pumpApp(home: tile());
    await tester.pump();
    expect(resolutions, 1);

    // The grid rebuilds on every keystroke in the search box and on every cart
    // tap. Each of those used to start the resolution over, and the
    // placeholder flashed in and out.
    await tester.pumpApp(home: tile());
    await tester.pump();
    await tester.pumpApp(home: tile());
    await tester.pump();
    await tester.pumpApp(home: tile());
    await tester.pump();

    expect(resolutions, 1, reason: 'the photograph is resolved once');
  });

  testWidgets('a rebuild does not put the placeholder back',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    Widget tile() => Scaffold(
          body: ProductPhoto(
            imagePath: 'product_photos/1.jpg',
            size: 56,
            resolve: (String path) async => photo.path,
          ),
        );

    await tester.pumpApp(home: tile());
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);

    // The photograph is still there in the very first frame after a rebuild.
    // Before, the snapshot reset to "waiting" and the placeholder replaced it
    // for a frame.
    await tester.pumpApp(home: tile());
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('the decode is sized for the screen it is drawn on',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    // A 3x screen: twice the drawn size is soft there.
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpApp(
      home: Scaffold(
        body: ProductPhoto(
          imagePath: 'product_photos/1.jpg',
          size: 56,
          resolve: (String path) async => photo.path,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The framework does not hand the decode size back, so the number the
    // widget used is exposed instead.
    expect(ProductPhoto.decodeWidthFor(56, 3), 168);
    expect(ProductPhoto.decodeWidthFor(56, 2), 112);
  });

  testWidgets('a product with no photograph is not drawn as a fault',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);

    await tester.pumpApp(
      home: Scaffold(
        body: ProductPhoto(imagePath: null, size: 56),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // "Image not supported" is a picture of something going wrong. Most
    // products have no photograph and never will, and the tile should say so
    // without looking like a fault report.
    expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('a photograph that cannot be decoded is not an error box',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);

    await tester.pumpApp(
      home: Scaffold(
        body: ProductPhoto(
          imagePath: 'product_photos/gone.jpg',
          size: 56,
          resolve: (String path) async => '${temp.path}/not-a-photo.jpg',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The same visual answer as having no photograph at all.
    expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
