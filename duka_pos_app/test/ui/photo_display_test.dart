// The photographs: a SAVED photo must be visible, and a MISSING one must fall
// back to the icon.
//
// This is the file that proves the whole chain, end to end: the bytes on disk,
// the relative path in the database, the resolver that turns that path back
// into a file, and the widget that draws it. A break anywhere in that chain
// shows the same way to the owner — "I saved it and it is not there" — and
// only one test can tell them apart.
//
// The resolver is exercised through the REAL store (a fake documents
// directory, the same seam `test/product_image_store_test.dart` uses), not
// through an injected function: an injected resolver proves the widget works,
// and the widget is not where the photographs went missing.
//
// TWO FACTS ABOUT A `testWidgets` BODY DRIVE THE SHAPE OF THIS FILE
//
//   * Real file I/O inside the body never completes on its own — the body runs
//     in a fake-async zone and the clock will not advance. So the photographs
//     are written in `setUp`, which is outside it, and the widget's own
//     resolve (which DOES touch the filesystem) is given a real moment through
//     `tester.runAsync`.
//   * A photograph that is written by `setUp` and read by the widget is the
//     only honest arrangement: a file that "exists" only inside the widget's
//     own future would prove nothing about the store.

import 'dart:io';

import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/screens/profile_screen.dart';
import 'package:duka_pos/services/app_state.dart';
import 'package:duka_pos/ui/components/product_photo.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/widgets/product_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import '../support/harness.dart';

/// A documents directory the test owns, so nothing touches the real one.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

/// A picker that always hands back the same file.
///
/// The real picker needs a camera roll and a platform channel, so a screen
/// that reaches the platform directly is a screen nobody can test.
class _FakePicker extends ImagePicker {
  _FakePicker(this.file);

  final File file;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async =>
      XFile(file.path);
}

/// The photograph that IS there: the one the editor saved.
const String savedPath = 'product_photos/legacy/5.jpg';

/// The photograph that is NOT there: the row says there is one and the file
/// was not part of the backup this device was restored from.
const String missingPath = 'product_photos/legacy/9.jpg';

/// A decodable JPEG at [relativePath], inside the fake documents directory.
Future<File> writePhoto(Directory docs, String relativePath) async {
  final File file = File('${docs.path}/$relativePath');
  await file.parent.create(recursive: true);
  final img.Image image = img.Image(width: 120, height: 120);
  img.fill(image, color: img.ColorRgb8(200, 40, 40));
  await file.writeAsBytes(img.encodeJpg(image, quality: 90));
  return file;
}

void main() {
  late Directory docs;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('photo_display_');
    PathProviderPlatform.instance = _FakePathProvider(docs);

    await writePhoto(docs, savedPath);
  });

  tearDown(() async {
    if (docs.existsSync()) await docs.delete(recursive: true);
  });

  /// Advances the real event loop and the fake clock together, until
  /// [condition] holds.
  ///
  /// The save the profile screen makes is real file I/O, and a `testWidgets`
  /// body runs in a fake-async zone where real I/O does not complete on its
  /// own: the read finishes on the REAL event loop, and the answer is only
  /// delivered into the widget when the fake clock is pumped. So the two are
  /// alternated until the thing being waited for is true.
  ///
  /// A fixed number of rounds would be a guess, and a guess is a flaky test on
  /// a slow machine: the chain here is read → decode → write → read back →
  /// decode the pixels, and every step is a real await.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    String? description,
  }) async {
    for (int round = 0; round < 120; round++) {
      if (condition()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    fail(description ?? 'the condition never became true');
  }

  ProductTileData tileFor(Product product) => ProductTileData(
        product: product,
        inCart: 0,
        sellsAsVariants: false,
        variantCount: 0,
        cheapestPrice: null,
        canTap: true,
      );

  Product productWith(String? imagePath) => Product(
        id: 5,
        name: 'Kenyatta bread',
        category: 'Bakery',
        costPrice: Money.fromMajor(40),
        sellPrice: Money.fromMajor(60),
        stockQty: 12,
        reorderLevel: 3,
        updatedAt: '2026-01-01T00:00:00.000Z',
        imagePath: imagePath,
      );

  group('the till tile', () {
    testWidgets('a product with a saved photograph draws the photograph',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: Scaffold(
          body: ProductTile(data: tileFor(productWith(savedPath))),
        ),
      );
      await pumpUntil(
        tester,
        () => find.byType(Image).evaluate().isNotEmpty,
        description: 'the photograph was never drawn',
      );
      await tester.pump(const Duration(milliseconds: 50));

      // The photograph, not the placeholder.
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a product whose photograph is gone draws the placeholder',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: Scaffold(
          body: ProductTile(data: tileFor(productWith(missingPath))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the shared component the tile and the inventory row draw', () {
    testWidgets('a resolvable path renders an Image, not the placeholder',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: Scaffold(
          body: ProductPhoto(imagePath: savedPath, size: 40),
        ),
      );
      await pumpUntil(
        tester,
        () => find.byType(Image).evaluate().isNotEmpty,
        description: 'the photograph was never drawn',
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsNothing);
    });

    testWidgets('an unresolvable path renders the placeholder fallback',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: Scaffold(
          body: ProductPhoto(imagePath: missingPath, size: 40),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a REPLACED photograph at the same path is read again',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      // A photograph is replaced by writing a new picture OVER the file at the
      // same path, so the path cannot tell the widget that what it is drawing
      // is out of date. The revision is what says so.
      int resolutions = 0;
      Widget photo({required Object? revision}) => Scaffold(
            body: ProductPhoto(
              imagePath: savedPath,
              size: 40,
              revision: revision,
              resolve: (String path) async {
                resolutions++;
                return File('${docs.path}/$path').path;
              },
            ),
          );

      await tester.pumpApp(home: photo(revision: 'first'));
      await tester.pump();
      expect(resolutions, 1);

      // The row's `updated_at` moved, so the photograph may be a different one.
      await tester.pumpApp(home: photo(revision: 'second'));
      await tester.pump();
      await tester.pump();

      expect(resolutions, 2,
          reason: 'a replaced photograph is read again, not kept from the '
              'codec cache');
    });
  });

  group('the placeholder', () {
    testWidgets('is a picture outline, never a broken-image glyph',
        (WidgetTester tester) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: const Scaffold(body: ProductPhoto(imagePath: null, size: 56)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });
  });

  group('the profile avatar', () {
    late AppState state;

    setUp(() {
      state = AppState()
        ..owner = Owner(
          id: 1,
          name: 'Amina',
          pinHash: 'hash',
          email: 'amina@duka.co.ke',
          shopName: 'Corner Shop',
          createdAt: '2026-01-01T00:00:00.000Z',
        );
    });

    /// The account's photograph, already saved.
    ///
    /// Written HERE, in the group's `setUp`: a `testWidgets` body runs in a
    /// fake-async zone, and real file I/O inside one never completes — the
    /// test waits forever for a write the clock will not advance.
    setUp(() async {
      await writePhoto(docs, 'avatars/owner.jpg');
    });

    /// The profile screen, with the account already on the session.
    Widget profile({ImagePicker? picker}) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: state),
          ],
          child: ProfileScreen(picker: picker),
        );

    testWidgets('draws the photograph the account saved', (
      WidgetTester tester,
    ) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(home: profile());
      await pumpUntil(
        tester,
        () => find.byType(Image).evaluate().isNotEmpty,
        description: 'the avatar never drew the photograph',
      );
      await tester.pump(const Duration(milliseconds: 50));

      // The photograph, not the initials.
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('AM'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens the whole photograph when it is tapped', (
      WidgetTester tester,
    ) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(home: profile());
      await pumpUntil(
        tester,
        () => find.byType(Image).evaluate().isNotEmpty,
        description: 'the avatar never drew the photograph',
      );
      await tester.pump(const Duration(milliseconds: 50));

      // The avatar is a button, and it is at least a finger wide.
      final Finder avatar = find.byType(Image);
      expect(avatar, findsOneWidget);
      final Size size = tester.getSize(avatar);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));

      await tester.tap(avatar);
      await tester.pumpAndSettle();

      // The photograph, whole, over the screen.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
    });
  });

  group('the profile avatar, with a photograph just picked', () {
    late AppState state;

    /// The picture in the gallery. The account has none yet.
    late File gallery;

    setUp(() async {
      state = AppState()
        ..owner = Owner(
          id: 1,
          name: 'Amina',
          pinHash: 'hash',
          email: 'amina@duka.co.ke',
          shopName: 'Corner Shop',
          createdAt: '2026-01-01T00:00:00.000Z',
        );
      gallery = await writePhoto(docs, 'gallery/pick.jpg');
    });

    testWidgets('draws the photograph that was just picked', (
      WidgetTester tester,
    ) async {
      tester.useDevice(Device.small);

      await tester.pumpApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: state),
          ],
          child: ProfileScreen(picker: _FakePicker(gallery)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Nothing to draw yet: the account has no photograph.
      expect(find.byType(Image), findsNothing);

      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();

      // The save is real file I/O, so the real event loop has to be given a
      // moment to answer it — and the avatar reads the file back afterwards.
      await pumpUntil(
        tester,
        () => File('${docs.path}/avatars/owner.jpg').existsSync(),
        description: 'the photograph was never written to the avatar path',
      );
      await pumpUntil(
        tester,
        () => find.byType(Image).evaluate().isNotEmpty,
        description: 'the avatar never drew the photograph that was picked',
      );
      await tester.pump(const Duration(milliseconds: 50));

      // The photograph that was picked is the one on screen.
      expect(find.byType(Image), findsOneWidget);
      expect(
        File('${docs.path}/avatars/owner.jpg').existsSync(),
        isTrue,
        reason: 'the photograph is written where the avatar looks for it',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
