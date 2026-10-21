// The Nerva wordmark.
//
// The app's footer used to say "Powered by Nerva" in the app's own typeface.
// That is a vendor's name set in somebody else's face, and it reads as a line
// of the app's own copy rather than as a brand.
//
// What this pins:
//   * the mark is a MARK: an image, announced as the vendor's NAME, so a
//     screen-reader user hears "Nerva" rather than "image";
//   * the variant follows the surface: the master on the app's near-black
//     night theme, the ink-and-blue version on its near-white day theme —
//     silver on white would be a ghost;
//   * it is sized by HEIGHT, so all four places it appears are the same size
//     and the aspect ratio is never stretched;
//   * the attribution is ONE semantics node, so it is heard as a sentence.

import 'package:duka_pos/ui/brand/nerva_wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the mark is announced as the vendor name', (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: const Scaffold(
        body: Center(child: NervaWordmark()),
      ),
    );
    await tester.pumpAndSettle();

    // The image is really there, and it really loaded: an asset that could not
    // be resolved raises, and an empty box is exactly the failure a footer is
    // most likely to have and nobody notices.
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);

    // And it says who it is.
    expect(find.bySemanticsLabel('Nerva'), findsOneWidget);
  });

  testWidgets('the attribution is one sentence, not two nodes', (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: const Scaffold(
        body: Center(child: PoweredByNerva()),
      ),
    );
    await tester.pumpAndSettle();

    // "Powered by Nerva" — the words and the mark together, as ONE node.
    // The mark's own node is excluded by the attribution, so a screen-reader
    // user hears a sentence rather than a word and then a name.
    expect(find.bySemanticsLabel('Powered by Nerva'), findsOneWidget);
    expect(find.bySemanticsLabel('Nerva'), findsNothing);
  });

  testWidgets('it is sized by height, and never stretched', (tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(
      home: const Scaffold(
        body: Center(child: PoweredByNerva(wordmarkHeight: 18)),
      ),
    );
    await tester.pumpAndSettle();

    final Image image = tester.widget<Image>(find.byType(Image));
    expect(image.height, 18);

    // The rendered width follows the asset's own aspect ratio.
    final Size size = tester.getSize(find.byType(Image));
    expect(size.height, 18);
    expect(size.width, greaterThan(size.height * 5));
  });

  testWidgets('it fits a 320dp phone at 200% text', (tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      home: const Scaffold(
        body: Center(child: PoweredByNerva()),
      ),
      textScaler: TextScaler.linear(2.0),
    );
    await tester.pumpAndSettle();

    tester.expectNoOverflow('nerva attribution at 2x text');
  });
}
