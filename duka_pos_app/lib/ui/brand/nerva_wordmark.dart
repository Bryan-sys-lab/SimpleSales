// The Nerva wordmark.
//
// ## WHY A MARK AND NOT A WORD
//
// The app's footer used to say "Powered by Nerva" in the type of the app. That
// is a vendor's name rendered in somebody else's typeface, which makes it look
// like a line of the app's own copy — and a name set in the wrong face is a
// name nobody believes is a brand.
//
// The vendor's own mark is a CHROME WORDMARK with a blue "A", and it is
// recognisable in a way "Nerva" in Plus Jakarta Sans is not. So the footer
// shows the mark, and the words beside it shrink to the role they play: "Powered
// by".
//
// ## WHY TWO VARIANTS
//
// The master is silver on black. The app has a near-black night theme — close
// enough to the master's own ground that the mark reads exactly as generated —
// and a near-white day theme, where silver on white would be a ghost.
//
// So there are two assets, rendered by ONE script from ONE master:
// `assets/branding/generate_nerva_logo.py`. The day variant is the same
// wordmark in the app's own ink with the blue deepened for contrast; the
// night variant is the master, with the black ground removed.
//
// ## WHY THE HEIGHT IS FIXED AND THE WIDTH IS NOT
//
// The mark is a wide, short wordmark — about seven to one. Sizing it by WIDTH
// is what produces a footer that is a logo in one place and a banner in
// another, so it is sized by HEIGHT and the width follows the asset's own
// aspect ratio. Every place Nerva appears is then the same size.

import 'package:flutter/material.dart';

import '../../app_brand.dart';
import '../../l10n/generated/app_localizations.dart';

/// The Nerva wordmark, in the variant the current surface needs.
///
/// Sized by [height]: the width follows the asset's aspect ratio, so the mark
/// is the same size everywhere it appears.
class NervaWordmark extends StatelessWidget {
  const NervaWordmark({this.height = 13, super.key});

  /// The mark's height in logical pixels. The width is derived.
  final double height;

  /// The mark for a dark surface: the master, with its ground removed.
  static const String darkAsset = 'assets/branding/nerva_wordmark_dark.png';

  /// The mark for a light surface: the same wordmark in the app's ink.
  static const String lightAsset = 'assets/branding/nerva_wordmark_light.png';

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      // The mark IS the name, so it is announced as the name. A screen-reader
      // user hears "Nerva", not "image".
      label: SimplePosBrand.vendorName,
      image: true,
      excludeSemantics: true,
      child: Image.asset(
        dark ? darkAsset : lightAsset,
        height: height,
        // The width comes from the asset's own aspect ratio, so the mark is
        // never stretched.
        fit: BoxFit.contain,
        // The asset is already the right size for a 3x screen; letting Flutter
        // pick the nearest avoids a resample on a phone.
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// The attribution footer: the words, and the mark.
///
/// One widget, so all four places Nerva appears look the same and say the
/// same thing. The words are LOCALISED — "Powered by" is a sentence, and the
// app localises its sentences — while the mark is a brand constant and is not
/// localised at all.
class PoweredByNerva extends StatelessWidget {
  const PoweredByNerva({
    this.style,
    this.alignment = CrossAxisAlignment.center,
    this.wordmarkHeight = 13,
    super.key,
  });

  /// The style of the words beside the mark.
  final TextStyle? style;

  /// How the words and the mark sit together.
  final CrossAxisAlignment alignment;

  /// The mark's height in logical pixels.
  final double wordmarkHeight;

  @override
  Widget build(BuildContext context) {
    final String words = _poweredByLabel(context);

    return Semantics(
      // One node for the whole attribution, so a screen reader hears
      // "Powered by Nerva" rather than the words and the mark separately.
      label: '$words ${SimplePosBrand.vendorName}',
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: switch (alignment) {
          CrossAxisAlignment.start => WrapCrossAlignment.start,
          CrossAxisAlignment.end => WrapCrossAlignment.end,
          _ => WrapCrossAlignment.center,
        },
        runAlignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          Text(words, style: style),
          NervaWordmark(height: wordmarkHeight),
        ],
      ),
    );
  }
}

/// The words beside the mark, in the app's language.
///
/// Falls back to English when the localisations do not carry the key, so the
/// footer is never empty.
String _poweredByLabel(BuildContext context) {
  final AppLocalizations? l10n =
      Localizations.of<AppLocalizations>(context, AppLocalizations);
  return l10n?.poweredBy ?? 'Powered by';
}
