// A product's photograph, or the placeholder for "this one has none".
//
// ## Where this is used
//
// The SELL screen, and nowhere else. A product is a row in a list on every
// other screen — the inventory, the dashboard's low-stock alert, the analytics
/// tables — and a photograph in a list makes the list slower to scan (the eye
/// stops on every image) and slower to render, for no gain the owner asked for.
/// At the till a photograph is the thing a cashier matches against the shelf.
///
/// ## Why the widget takes a path and not a product
///
/// A shared component that takes a domain entity stops being shared: it can no
/// longer be pumped by a test without a whole product, and every caller drags
/// the model in. This takes a `String?` and knows nothing else.
///
/// ## Why the decode is sized
///
/// `cacheWidth` tells the codec to decode at the width actually drawn rather
/// than the source's. A photograph imported at 512px drawn into a 64px tile
/// would otherwise be decoded at 512 and scaled — four times the memory and
/// decode for bytes nobody sees.

library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/product_image_store.dart';

/// Draws [imagePath] at [size], or a neutral placeholder.
///
/// The placeholder is not an error state: most products have no photograph and
/// never will, so "no photo" must look intentional rather than broken.
class ProductPhoto extends StatelessWidget {
  const ProductPhoto({
    required this.imagePath,
    this.size = 64,
    super.key,
  });

  /// The relative path stored on the product, or null.
  final String? imagePath;

  /// The square edge to draw, in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(size / 6);
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: imagePath == null
            ? _placeholder(context)
            : FutureBuilder<String?>(
                future: ProductImageStore.resolve(imagePath),
                builder: (BuildContext context, AsyncSnapshot<String?> snap) {
                  final path = snap.data;
                  if (path == null) return _placeholder(context);
                  return Image.file(
                    _file(path),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    // Decoded at the drawn size, at 2x for a crisp render on a
                    // high-density screen. See the header.
                    cacheWidth: (size * 2).round(),
                    // A photograph that cannot be decoded — a file the shop
                    // deleted, or a backup restored without its images — is the
                    // same visual answer as having no photograph at all. Never
                    // an error box in the middle of the till grid.
                    errorBuilder: (_, __, ___) => _placeholder(context),
                  );
                },
              ),
      ),
    );
  }

  /// The file a resolved path names.
  ///
  /// Kept as a function rather than a field so the widget stays `const`-able
  /// where the caller has no image at all.
  File _file(String path) => File(path);

  /// "This product has no photograph."
  ///
  /// Deliberately quiet: an outline box with a slash, in the muted token, so it
  /// reads as "not set" rather than as something that failed.
  Widget _placeholder(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: size * 0.4,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
