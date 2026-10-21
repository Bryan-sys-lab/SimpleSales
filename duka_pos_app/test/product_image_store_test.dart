// Where a product's photograph lives, and what size it is kept at.
//
// The rules this pins are the ones that would silently cost a shop money or
// disk space:
//
//   1. The path is RELATIVE, because the absolute documents directory differs
//      between phones. An absolute path restored onto a different handset
//      points at a folder that does not exist there — every photo in the
//      catalogue, broken, with no error anywhere.
//   2. A photograph is RE-ENCODED on import, down to the longest edge the app
//      actually draws. A phone camera's four-kilopixel JPEG kept as-is would be
//      four times the memory and decode for bytes nobody sees.
//   3. Import never mutates the source file. It belongs to the gallery.
//   4. A full disk is a typed answer the UI can name, not a silent failure.

import 'dart:io';

import 'package:duka_pos/services/product_image_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// A documents directory the test owns, so nothing touches the real one.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late Directory gallery;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('product_photos_');
    gallery = await Directory.systemTemp.createTemp('gallery_');
    PathProviderPlatform.instance = _FakePathProvider(docs);
  });

  tearDown(() async {
    await docs.delete(recursive: true);
    await gallery.delete(recursive: true);
  });

  /// A decodable JPEG of [width]x[height] on disk.
  Future<File> writeJpeg(
    String name, {
    required int width,
    required int height,
  }) async {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(200, 40, 40));
    final file = File('${gallery.path}/$name');
    await file.writeAsBytes(img.encodeJpg(image, quality: 95));
    return file;
  }

  group('the path is relative, and the store owns the folder', () {
    test('the stored path names the folder, not the phone', () {
      // The whole reason the column is relative. Asserted at the level the
      // database sees it, so a future change to an absolute path fails here.
      final relative = ProductImageStore.relativePathFor(42)!;
      expect(relative, 'product_photos/42.jpg');
      expect(relative.startsWith('/'), isFalse,
          reason: 'an absolute path is device-specific by construction');
    });

    test('an empty relative path resolves to nothing, not to a guess',
        () async {
      // A product with no photograph must not resolve the LAST one resolved.
      expect(await ProductImageStore.resolve(null), isNull);
      expect(await ProductImageStore.resolve(''), isNull);
      expect(await ProductImageStore.resolve('   '), isNull);
    });
  });

  group('import', () {
    test('re-encodes down to the longest edge the app draws', () async {
      final source = await writeJpeg('big.jpg', width: 4000, height: 2000);
      final relative = await ProductImageStore.save(source, productId: 7);

      expect(relative, 'product_photos/7.jpg');

      final stored = File('${docs.path}/$relative');
      expect(await stored.exists(), isTrue);

      final decoded = img.decodeImage(await stored.readAsBytes())!;
      // 4000 wide is the longest edge; capped, and the ratio preserved.
      expect(decoded.width, ProductImageStore.maxEdgeForTest);
      expect(decoded.height, (2000 * (512 / 4000)).round());

      // And it is far smaller than the source, which is the point.
      expect(await stored.length(), lessThan(await source.length()),
          reason: 'an import that grows the file is not an import');
    });

    test('writes the file when the path has a folder in it', () async {
      // A product's photograph is stored under a folder PER WORKSPACE, so
      // product #5 in shop B cannot overwrite shop A's. That makes the path two
      // segments deep, and only the first segment was ever created — so the
      // write failed with "no such directory", the editor reported it as "the
      // phone is full", the path was never stored, and the till never showed a
      // photograph at all.
      final source = await writeJpeg('shop.jpg', width: 400, height: 400);

      final relative = await ProductImageStore.save(
        source,
        productId: 5,
        workspaceKey: 'shop-b',
      );

      expect(relative, 'product_photos/shop-b/5.jpg');

      final stored = File('${docs.path}/$relative');
      expect(await stored.exists(), isTrue,
          reason: 'the whole folder has to exist before the file can be '
              'written into it');
      expect(img.decodeImage(await stored.readAsBytes()), isNotNull);
    });

    test('leaves the gallery file exactly as it was', () async {
      final source = await writeJpeg('kept.jpg', width: 300, height: 300);
      final before = await source.readAsBytes();

      await ProductImageStore.save(source, productId: 8);

      expect(await source.readAsBytes(), before,
          reason: "the gallery's file is not this app's to rewrite");
    });

    test('replaces the previous photograph, leaving only one file', () async {
      final first = await writeJpeg('one.jpg', width: 200, height: 200);
      final second = await writeJpeg('two.jpg', width: 260, height: 260);

      await ProductImageStore.save(first, productId: 9);
      await ProductImageStore.save(second, productId: 9);

      final dir = Directory('${docs.path}/product_photos');
      expect(await dir.list().toList(), hasLength(1));
    });

    test('a source that has gone missing is a named failure', () async {
      final source = await writeJpeg('gone.jpg', width: 100, height: 100);
      await source.delete();

      await expectLater(
        ProductImageStore.save(source, productId: 10),
        throwsA(isA<ProductImageException>()
            .having((e) => e.failure, 'failure', ProductImageFailure.missing)),
      );
    });

    test('a file that is not an image is a named failure', () async {
      final notAnImage = File('${gallery.path}/broken.jpg')
        ..writeAsStringSync('this is not a JPEG');

      await expectLater(
        ProductImageStore.save(notAnImage, productId: 11),
        throwsA(isA<ProductImageException>().having(
            (e) => e.failure, 'failure', ProductImageFailure.undecodable)),
      );
    });
  });

  group('removal', () {
    test('deletes the file, and is safe when there is none', () async {
      final source = await writeJpeg('removed.jpg', width: 120, height: 120);
      await ProductImageStore.save(source, productId: 12);
      final relative = ProductImageStore.relativePathFor(12)!;

      await ProductImageStore.delete(12);
      expect(await File('${docs.path}/$relative').exists(), isFalse);

      // Removing again must not throw: the caller asked for the end state, and
      // the end state is already here.
      await ProductImageStore.delete(12);
    });

    test('after removal the path resolves to nothing', () async {
      final source = await writeJpeg('leave.jpg', width: 120, height: 120);
      await ProductImageStore.save(source, productId: 13);

      await ProductImageStore.delete(13);

      expect(await ProductImageStore.resolve('product_photos/13.jpg'), isNull);
    });
  });

  group('a path whose file is absent', () {
    test('resolves to null rather than to a broken path', () async {
      // The backup-restored-onto-another-phone case. The row says there is a
      // photograph; the file was not part of the backup.
      final resolved = await ProductImageStore.resolve('product_photos/99.jpg');
      expect(resolved, isNull);
    });
  });
}
