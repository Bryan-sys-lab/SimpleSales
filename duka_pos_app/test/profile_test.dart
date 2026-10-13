// The account profile's two load-bearing rules.
//
//   1. The address is SHOWN MASKED. This is the screen that exists to display
//      the owner's own details, so if it shows the address in full then nowhere
//      else has to either — and a phone read on a shop floor is read by
//      whoever is standing behind the person at the counter.
//   2. The avatar is a per-DEVICE file, not a per-shop one. An owner running
//      several shops on one handset is the same person in all of them; naming
//      the file after the workspace would make a photo picked for one shop
//      invisible in the others.
//
// Both are invisible in a screenshot, which is exactly why they are tested.

import 'dart:io';

import 'package:duka_pos/services/pin_reset_service.dart';
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

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('profile_');
    PathProviderPlatform.instance = _FakePathProvider(docs);
  });

  tearDown(() async => docs.delete(recursive: true));

  Future<File> writeJpeg(String name,
      {int width = 200, int height = 200}) async {
    final gallery = Directory('${docs.path}/gallery');
    await gallery.create(recursive: true);
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(40, 120, 200));
    return File('${gallery.path}/$name')
      ..writeAsBytesSync(img.encodeJpg(image, quality: 95));
  }

  group('the address is masked wherever it is shown', () {
    test('the local part goes, the domain stays', () {
      final masked = PinResetService.maskEmail('amina@duka.co.ke');
      expect(masked, 'a***@duka.co.ke');
      expect(masked, isNot(contains('amina')),
          reason: 'the part that names the person');
      expect(masked, contains('duka.co.ke'),
          reason: 'the part someone checking a typo looks at');
    });

    test('a one-character local part does not vanish', () {
      expect(PinResetService.maskEmail('a@b.co'), 'a***@b.co');
    });

    test('an empty address masks to nothing, not to a partial address', () {
      expect(PinResetService.maskEmail(''), '');
      expect(PinResetService.maskEmail('   '), '   ');
    });
  });

  group('the avatar is per device, not per shop', () {
    test('its path names no workspace', () {
      // THE rule. Naming it after the workspace would mean a photo picked for
      // one shop is invisible in the others, and a shop with two on one
      // handset would have two avatars for one person.
      expect(ProductImageStore.avatarRelativePath, 'avatars/owner.jpg');
    });

    test('and it does not collide with a product photograph', () {
      expect(ProductImageStore.relativePathFor(42), 'product_photos/42.jpg');
      expect(
        ProductImageStore.avatarRelativePath.split('/').first,
        isNot(ProductImageStore.relativePathFor(42)!.split('/').first),
      );
    });
  });

  group('picking one', () {
    test('stores it and resolves back to a readable file', () async {
      final source = await writeJpeg('avatar.jpg');

      final relative = await ProductImageStore.saveAvatar(source);
      expect(relative, ProductImageStore.avatarRelativePath);

      final resolved = await ProductImageStore.resolve(relative);
      expect(resolved, isNotNull);
      expect(await File(resolved!).exists(), isTrue);
      // The source is the gallery's file and is left alone: it belongs to the
      // app the shop picked it from.
      expect(await source.exists(), isTrue);
    });

    test('replacing it leaves exactly one file, not a pile', () async {
      await ProductImageStore.saveAvatar(await writeJpeg('a.jpg'));
      await ProductImageStore.saveAvatar(
          await writeJpeg('b.jpg', width: 400, height: 400));

      final dir = Directory('${docs.path}/avatars');
      expect(await dir.list().toList(), hasLength(1));
    });

    test('re-encodes down to the longest edge the app draws', () async {
      // A phone camera's output is far larger than the 96dp circle this is
      // shown in; keeping the original would spend memory and decode on bytes
      // nobody sees.
      final source = await writeJpeg('big.jpg', width: 2000, height: 1500);
      await ProductImageStore.saveAvatar(source);

      final stored = File('${docs.path}/avatars/owner.jpg');
      final decoded = img.decodeImage(await stored.readAsBytes())!;
      expect(decoded.width, ProductImageStore.maxEdgeForTest);
      expect(decoded.height, (1500 * (512 / 2000)).round());
    });

    test('a shop that has never picked one reads as "no photo", not as broken',
        () async {
      expect(
        await ProductImageStore.resolve(ProductImageStore.avatarRelativePath),
        isNull,
      );
    });
  });
}
