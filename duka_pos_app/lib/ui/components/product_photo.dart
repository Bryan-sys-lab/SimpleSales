// A product's photograph, or the placeholder for "this one has none".
//
// ## Where this is used
//
// The SELL screen — a photograph is the thing a cashier matches against the
// shelf — and the INVENTORY row, where the owner is managing the photographs
// and has to see which product the one they are looking at belongs to.
//
// It is deliberately NOT on the dashboard's low-stock list or the analytics
// tables: a photograph in a list of figures is a picture the eye stops on and
// a number nobody was reading.
//
// ## Why the widget takes a path and not a product
//
// A shared component that takes a domain entity stops being shared: it can no
// longer be pumped by a test without a whole product, and every caller drags
// the model in. This takes a `String?` and knows nothing else.
//
// ## Why the path is resolved ONCE
//
// Resolving means asking the platform where the app's documents folder is and
// then asking the filesystem whether the file is there — two awaits, on every
// single build.
//
// A `FutureBuilder` that is handed a NEW future on every build starts over:
// the snapshot goes back to "waiting", so the "no photograph" placeholder
// flashes in and out on every rebuild of the till grid. And the till grid
// rebuilds on every keystroke in the search box and on every cart tap, so the
// photographs flashed constantly — a shop full of products with pictures, and
// the pictures blinked.
//
// So the future is held in the widget's state and replaced only when the path
// changes. The photograph stays.
//
// The future is also not handed to a `FutureBuilder`: that widget takes the
// snapshot back to "waiting" whenever it is given a NEW future, and a
// `FutureBuilder` that re-resolves is a placeholder that flashes in and out on
// every rebuild of the till grid.
//
// ## Why the decode is sized
//
// `cacheWidth` tells the codec to decode at the width actually drawn rather
// than the source's. A photograph imported at 512px drawn into a 64px tile
// would otherwise be decoded at 512 and scaled — four times the memory and
// decode for bytes nobody sees.
//
// The width is the DRAWN size times the screen's pixel ratio, not a flat
// multiple: a 2x guess is soft on a 3x phone, and a 3x guess is wasteful on a
// 2x one. The phone's own ratio is the answer to "how many device pixels is
// this worth".
//
// ## Why a photograph can be REPLACED under the widget's feet
//
// The app writes a new photograph OVER the file at the same path, so the
// path cannot tell a widget that the picture behind it changed. And the
// codec's cache is keyed by that path, so the OLD pixels are what the
// framework hands back: the shop picks a new picture, the app saves it, and
// the till goes on showing the photograph that was there before.
//
// So the widget is told twice: [revision] says "the file behind this path
// may be a different photograph now", and the decoded entry for the path is
// forgotten before the photograph is asked for again. The version in the
// [Image]'s key is what makes the framework ask again at all.
//
// ## Why [PhotoImage] lives here
//
// The version-key and the eviction are two halves of ONE trick, and every
// caller that draws a photograph needs both — the till tile, the inventory
// row, and the profile avatar. A caller that draws half of it is a caller
// whose photograph goes stale, so the two halves are one file and one pair of
// imports, and a caller cannot take one without the other.

library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/product_image_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_shapes.dart';

/// Draws [imagePath] at [size], or a neutral placeholder.
///
/// The placeholder is not an error state: most products have no photograph and
/// never will, so "no photo" must look intentional rather than broken.
class ProductPhoto extends StatefulWidget {
  const ProductPhoto({
    required this.imagePath,
    this.size = 64,
    this.resolve,
    this.revision,
    super.key,
  });

  /// The relative path stored on the product, or null.
  final String? imagePath;

  /// The square edge to draw, in logical pixels.
  final double size;

  /// Resolves the stored path to an absolute one.
  ///
  /// INJECTED so the widget can be pumped in a test: resolving means asking
  /// the platform where the app's documents folder is, and a widget whose only
  /// path to a photograph is the platform is a widget nobody can test. Null
  /// means "ask the store", which is what the app does.
  final Future<String?> Function(String relativePath)? resolve;

  /// Says that the FILE behind [imagePath] may be a different photograph.
  ///
  /// The path does not change when a photograph is replaced — the new picture
  /// is written over the old file — so the path alone cannot tell this widget
  /// that what it is drawing is out of date. Whatever the caller knows about
  /// the row's freshness goes here: the product's `updated_at`, the counter
  /// the profile screen bumps after a save.
  ///
  /// A change here makes the widget read the file again and draw what is in
  /// it NOW.
  final Object? revision;

  /// The pixel width a photograph drawn at [size] is decoded at.
  ///
  /// The screen's own pixel ratio, not a guess: a photograph decoded at 2x and
  /// drawn on a 3x screen is soft, and one decoded at 4x on a 2x screen is
  /// four times the memory for pixels nobody sees.
  ///
  /// Public because it is a number the picture depends on, and the framework
  /// does not hand it back for a test to read.
  @visibleForTesting
  static int decodeWidthFor(double size, double devicePixelRatio) =>
      (size * devicePixelRatio).round();

  @override
  State<ProductPhoto> createState() => _ProductPhotoState();
}

class _ProductPhotoState extends State<ProductPhoto> {
  /// The resolved absolute path, once.
  ///
  /// Held here rather than handed to a `FutureBuilder` on every build: see
  /// the header. Replaced only when the path itself changes.
  late Future<String?> _resolved;

  /// What the future resolved to. Null until it does, and null forever for a
  /// product with no photograph.
  String? _path;

  /// Bumped every time the photograph is read.
  ///
  /// It is part of the [Image]'s key, so the framework asks for the
  /// photograph afresh instead of keeping the frame it drew last time.
  int _version = 0;

  /// The decode width the last build used.
  ///
  /// The codec's cache is keyed by the path AND the decode width, so the
  /// entry to forget is the one that was written. Null until the first build
  /// — before it, nothing has been decoded and nothing can be stale.
  int? _cacheWidth;

  @override
  void initState() {
    super.initState();
    _resolved = _resolve();
    _resolved.then(_onResolved);
  }

  @override
  void didUpdateWidget(covariant ProductPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different photograph is a different answer, and so is the SAME
    // photograph that was replaced on disk. The SIZE is neither: the path
    // does not depend on it, and the decode is sized per build.
    if (oldWidget.imagePath != widget.imagePath ||
        oldWidget.revision != widget.revision) {
      _resolved = _resolve();
      _resolved.then(_onResolved);
    }
  }

  /// The future's answer, applied once.
  ///
  /// `mounted` first: a tile scrolled out of the till grid mid-resolve must not
  /// set state on a widget the framework has already thrown away.
  void _onResolved(String? path) {
    if (!mounted) return;
    setState(() {
      _path = path;
      _version++;
    });
  }

  Future<String?> _resolve() async {
    final String? path = widget.imagePath;
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    final String? resolved =
        await (widget.resolve?.call(path) ?? ProductImageStore.resolve(path));
    final int? width = _cacheWidth;
    if (resolved != null && width != null) {
      // The file at this path may be a DIFFERENT photograph from the one the
      // codec cached under it. Forget the old one before the new one is asked
      // for, or the old pixels are what gets drawn.
      await forgetDecodedPhoto(resolved, cacheWidth: width);
    }
    return resolved;
  }

  @override
  Widget build(BuildContext context) {
    final String? path = _path;
    return ClipRRect(
      borderRadius: AppShapes.of(context).controlRadius,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: path == null ? _placeholder(context) : _image(context, path),
      ),
    );
  }

  /// The photograph itself.
  Widget _image(BuildContext context, String path) {
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    final int cacheWidth = ProductPhoto.decodeWidthFor(widget.size, ratio);
    _cacheWidth = cacheWidth;

    return PhotoImage(
      path: path,
      size: widget.size,
      // The version is what makes the framework ask for the photograph again
      // instead of keeping the frame it drew last time. Without it a
      // photograph that was replaced on disk is still the old one on screen.
      version: _version,
      cacheWidth: cacheWidth,
      // The previous frame stays on screen until the next one is ready, so a
      // photograph does not blink to the placeholder and back as the grid
      // scrolls under the finger.
      gaplessPlayback: true,
      // A photograph that cannot be decoded — a file the shop deleted, or a
      // backup restored without its images — is the same visual answer as
      // having no photograph at all. Never an error box in the middle of the
      // till grid.
      errorBuilder: (_, __, ___) => _placeholder(context),
    );
  }

  /// "This product has no photograph."
  ///
  /// A picture outline, and deliberately NOT the "image not supported" glyph:
  /// that one has a slash through it, which is a picture of something going
  /// wrong. Most products have no photograph and never will, and the tile
  /// should say so without looking like a fault report.
  Widget _placeholder(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return ColoredBox(
      // A sunken well, not a container-ladder colour: the placeholder is a
      // HOLE where a photograph would be, and a hole is darker than the tile
      // around it.
      color: colors.surfaceSunken,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: widget.size * 0.4,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Draws the photograph at [path].
///
/// The plain file image, plus the two things a photograph on disk needs and a
/// bare `Image.file` does not: a key that says "the file behind this path may
/// be a different photograph now", and an escape hatch for a file that cannot
/// be decoded.
class PhotoImage extends StatelessWidget {
  const PhotoImage({
    required this.path,
    required this.size,
    this.version = 0,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.semanticLabel,
    this.gaplessPlayback = false,
    this.errorBuilder,
    super.key,
  });

  /// The absolute path of the photograph.
  final String path;

  /// The edge of the box it is drawn in, in logical pixels.
  final double size;

  /// Changes when the FILE behind [path] may be a different photograph.
  ///
  /// It is in the [Image]'s key, so the framework asks for the photograph
  /// afresh instead of keeping the frame it drew last time.
  final Object? version;

  /// How the photograph fills the box.
  final BoxFit fit;

  /// The width the photograph is decoded at, in device pixels.
  ///
  /// The width it is DRAWN at is not the width it is DECODED at: a photograph
  /// imported at 512px drawn into a 56px tile would otherwise be decoded at
  /// 512 and scaled — four times the memory and decode for bytes nobody sees.
  final int? cacheWidth;

  /// What a screen reader announces for the photograph, if anything.
  final String? semanticLabel;

  /// Whether the previous frame stays on screen until the next one is ready.
  ///
  /// On the till grid, yes: a photograph that blinks to the placeholder and
  /// back as the grid scrolls under the finger is a photograph nobody can
  /// match against the shelf.
  final bool gaplessPlayback;

  /// What to draw when the file cannot be decoded.
  ///
  /// A photograph that has moved or been deleted is the same visual answer as
  /// never having had one, rather than a broken-image glyph in the middle of
  /// the till grid.
  final Widget Function(BuildContext context, Object error, StackTrace? stack)?
      errorBuilder;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      key: ValueKey<Object?>(version),
      width: size,
      height: size,
      fit: fit,
      cacheWidth: cacheWidth,
      semanticLabel: semanticLabel,
      gaplessPlayback: gaplessPlayback,
      errorBuilder: errorBuilder,
    );
  }
}

/// Forgets the decoded photograph at [path], so the next ask decodes the file
/// as it is NOW.
///
/// The codec's cache is keyed by the file path AND the decode width, and the
/// app writes a new photograph over the file at the same path — so the entry
/// in that cache is the OLD photograph, and asking for it again hands back the
/// old pixels.
///
/// [cacheWidth] has to be the width the photograph is drawn at: a different
/// decode width is a different cache entry, and forgetting the wrong one
/// leaves the stale pixels exactly where they were.
///
/// The key is the provider's own cache key: the framework builds it inside
/// `ResizeImage` and does not hand it out.
Future<void> forgetDecodedPhoto(
  String path, {
  required int cacheWidth,
}) async {
  final ImageProvider<Object> provider =
      ResizeImage(FileImage(File(path)), width: cacheWidth);
  await provider.evict();
}
