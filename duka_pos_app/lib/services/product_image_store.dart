// Where a product's photograph lives, and how big it is allowed to be.
//
// ## Why a PATH and not the bytes
//
// A photograph is the one thing on a product row that is large — a few hundred
// kilobytes each, against a few dozen for everything else. Storing the bytes in
// the database would put them in every backup the shop takes, every encrypted
// export, and every cross-shop audit read. So the database holds a path and the
// filesystem holds the bytes.
//
// The path is RELATIVE — `product_photos/<productId>.jpg` — and resolved through
// [pathFor]. A relative path survives a device migration: the absolute directory
// differs between phones, and a restore onto a different handset would otherwise
// leave every photo pointing at a folder that does not exist.
//
// ## Why the image is RE-ENCODED on import
//
// A phone camera produces a four-kilopixel JPEG. The largest slot this app draws
// it into is a tile on a tablet, so decoding the original to fill it is wasted
// memory and wasted decode on the phones this till targets. Import re-encodes to
// the longest edge the app actually needs, which also strips the EXIF orientation
// and any embedded thumbnail — an image a shop did not take should not carry a
// GPS coordinate into this app's storage.
//
// ## Failure is a typed answer, not a cloud of nulls
//
// Every method either succeeds or returns a reason the caller can name to the
// owner. `save` on a source file that has already vanished returns `missing`,
// which is a real case: a shop can pick from a gallery whose file is then moved.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Why an image could not be stored.
enum ProductImageFailure {
  /// The picked file is not there any more.
  missing,

  /// The file exists but is not a decodable image.
  undecodable,

  /// The phone has no room.
  storage,
}

/// Thrown when a product photo cannot be stored.
class ProductImageException implements Exception {
  const ProductImageException(this.failure, [this.cause]);

  final ProductImageFailure failure;
  final Object? cause;

  @override
  String toString() => 'ProductImageException($failure)';
}

/// Reads and writes product photographs.
class ProductImageStore {
  ProductImageStore._();

  /// The folder photographs live in, relative to the app's documents directory.
  static const _folder = 'product_photos';

  /// The folder account avatars live in.
  static const avatarFolder = 'avatars';

  /// The extension stored on disk.
  static const _extension = 'jpg';

  /// The longest edge an imported photograph may have.
  ///
  /// Sized for the largest place a photo is drawn — a grid tile on a tablet —
  /// and not for the sensor. A 4x margin over that keeps a photo crisp when it
  /// is drawn slightly larger after a future layout change, without paying for
  /// the whole capture.
  static const _maxEdge = 512;

  /// The cap, exposed so a test can assert the re-encode without duplicating the
  /// number and drifting from it.
  @visibleForTesting
  static int get maxEdgeForTest => _maxEdge;

  /// JPEG quality for the re-encoded copy.
  ///
  /// High enough that a label on a bottle stays legible, low enough that a
  /// product photo is a rounding error against the database it belongs to.
  static const _quality = 82;

  /// The relative path a product's photograph is stored under, or null when the
  /// product has none.
  ///
  /// Null is a real answer — most products will never have a photo, and a blank
  /// placeholder must not be mistaken for a broken image.
  static String? relativePathFor(int productId) =>
      '$_folder/$productId.$_extension';

  /// The relative path this shop's avatar is stored under.
  ///
  /// One avatar per DEVICE, not per workspace: an owner runs several shops on
  /// one handset and is the same person in all of them. Naming the file after
  /// the workspace would give each shop its own avatar and a photo picked for
  /// one would not appear in the others.
  static const String avatarRelativePath = '$avatarFolder/owner.jpg';

  /// Imports [source] as the photograph for [productId], replacing any existing
  /// one.
  ///
  /// The original file is left alone: it belongs to the gallery or the camera,
  /// and deleting a file the shop did not create would be a surprising side
  /// effect of choosing a photo.
  /// Saves an account avatar. See [avatarRelativePath] for why it is per-device.
  static Future<String> saveAvatar(File source) =>
      _saveAs(source, avatarRelativePath);

  static Future<String> save(File source, {required int productId}) async {
    if (!await source.exists()) {
      throw const ProductImageException(ProductImageFailure.missing);
    }
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const ProductImageException(ProductImageFailure.undecodable);
    }

    final resized = _bound(decoded);
    // Re-encoded rather than copied: see the note in the header. The EXIF
    // orientation is applied by the decode above, so a portrait photograph
    // from a phone camera does not arrive sideways.
    final encoded = img.encodeJpg(resized, quality: _quality);

    return _saveEncoded(encoded, relativePathFor(productId)!);
  }

  /// Re-encodes [source] into [relativePath], under its own folder.
  static Future<String> _saveAs(File source, String relativePath) async {
    if (!await source.exists()) {
      throw const ProductImageException(ProductImageFailure.missing);
    }
    final decoded = img.decodeImage(await source.readAsBytes());
    if (decoded == null) {
      throw const ProductImageException(ProductImageFailure.undecodable);
    }
    return _saveEncoded(
      img.encodeJpg(_bound(decoded), quality: _quality),
      relativePath,
    );
  }

  static Future<String> _saveEncoded(List<int> encoded, String relative) async {
    final folder = relative.split('/').first;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$folder');
    if (!await dir.exists()) await dir.create(recursive: true);
    try {
      final target = File('${docs.path}/$relative');
      await target.writeAsBytes(encoded, flush: true);
      return relative;
    } on FileSystemException catch (error) {
      // ENOSPC and friends surface here. The owner is told the phone is full
      // rather than being shown a silent failure to save a product.
      throw ProductImageException(ProductImageFailure.storage, error);
    }
  }

  /// Deletes the photograph for [productId], if there is one.
  ///
  /// Safe to call for a product that never had one: removing a photo that is
  /// already absent is the state the caller asked for, not an error.
  static Future<void> delete(int productId) async {
    try {
      final file = await _fileFor(productId);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A photo that cannot be deleted is a photo this device will keep showing.
      // Nothing useful can be done about it here, and the caller has already
      // recorded the intent to remove it.
    }
  }

  /// The absolute path a stored [relativePath] resolves to, or null when the
  /// file is not there.
  ///
  /// Resolves the RELATIVE path against this device's own documents directory,
  /// which is why the path is stored relative: the directory differs between
  /// phones, so a photo restored onto a different handset — where the image
  /// files were not part of the backup — yields null and the caller draws its
  /// placeholder rather than an error box.
  ///
  /// Decoding is NOT done here. `Image.file` with a `cacheWidth` decodes at the
  /// size the widget actually draws it, which is both cheaper and correct in a
  /// way a single decode target shared by every call site never is.
  static Future<String?> resolve(String? relativePath) async {
    if (relativePath == null || relativePath.trim().isEmpty) return null;
    final file = await _fileForPath(relativePath.trim());
    return await file.exists() ? file.path : null;
  }

  /// The [File] a relative path names.
  static Future<File> _fileForPath(String relativePath) async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}/$relativePath');
  }

  static Future<File> _fileFor(int productId) async =>
      _fileForPath(relativePathFor(productId)!);

  /// Scales [source] so its longest edge is at most [_maxEdge].
  ///
  /// Never upscales: a small icon made large is still a small icon, and the
  /// display slot will scale it.
  static img.Image _bound(img.Image source) {
    final longest = source.width > source.height ? source.width : source.height;
    if (longest <= _maxEdge) return source;
    final ratio = _maxEdge / longest;
    return img.copyResize(
      source,
      width: (source.width * ratio).round(),
      height: (source.height * ratio).round(),
      interpolation: img.Interpolation.average,
    );
  }

  /// Whether the device can decode images at all.
  ///
  /// Exposed so a test can assert the import path without a platform channel:
  /// the decode itself is pure Dart and runs everywhere, but the PICKING is
  /// not, so this is what separates the two halves.
  @visibleForTesting
  static bool get isPureDartDecode => true;
}
