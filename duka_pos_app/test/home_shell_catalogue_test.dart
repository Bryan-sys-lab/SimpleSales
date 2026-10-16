// The catalogue-change signal, which has to work from ABOVE the shell.
//
// This is the regression test for the shipped bug: product detail, shot cups
// and the imports answer are pushed on the ROOT navigator, so they sit outside
// the subtree that provides `HomeShellTabs`. `context.read<HomeShellTabs>()`
// threw `ProviderNotFoundException` there — AFTER the row had been written, and
// BEFORE the screen reloaded, so the owner's saved cup appeared in no list and
// on no till shelf. "I created a cup and nothing happened."
//
// A signal only the shell can fire is one the screens that most need it cannot
// use, so it lives at module level and the shell listens to it.

import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/routing/home_shell.dart';

void main() {
  setUp(() {
    // Module-level state shared by the whole file, so a test that only reads it
    // must not depend on the order the others ran in.
    resetCatalogueGenerationForTesting();
    catalogueListenersForTesting.clear();
  });

  group('a screen above the shell can announce a catalogue change', () {
    test('announcing with no shell anywhere is safe, and still counts', () {
      // A screen can save a product before the shell exists — a deep link, or a
      // test — and the next screen to read the catalogue reads the database.
      markCatalogueChanged();
      markCatalogueChanged();
      expect(catalogueGeneration, 2);
    });

    test('a listener inside the shell hears it', () {
      final List<int> heard = <int>[];
      void listener() => heard.add(catalogueGeneration);

      catalogueListenersForTesting.add(listener);
      addTearDown(() => catalogueListenersForTesting.remove(listener));

      markCatalogueChanged();

      expect(heard, hasLength(1),
          reason: 'a save made above the shell must reach the shell');
      expect(heard.single, greaterThan(0));
    });

    test('the generation moves by exactly one per announcement', () {
      expect(catalogueGeneration, 0);
      markCatalogueChanged();
      final int first = catalogueGeneration;
      markCatalogueChanged();
      expect(catalogueGeneration, first + 1);
    });

    test('an announcement reaches every listener, not just the last', () {
      // Two listeners, both kept: the sell screen and the shell's own chrome.
      int first = 0;
      int second = 0;
      catalogueListenersForTesting.add(() => first++);
      catalogueListenersForTesting.add(() => second++);

      markCatalogueChanged();

      expect(first, 1);
      expect(second, 1);
    });
  });
}
