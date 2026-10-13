// Finishing the rows an import asked about.
//
// The bug: an import refused a row missing its price rather than inventing one
// — the right call, and then a dead end. The row was kept on the
// needs-attention list, the dashboard told the owner to re-import the
// spreadsheet, and nothing in the app let them answer. A feature that asks a
// question and provides no way to answer it is worse than one that never asked.
//
// The property that matters: what the draft pre-fills is exactly what the
// import would have written, and what it reports missing is exactly what the
// import refused on. Both go through the import's own parsers, so a draft can
// never disagree with the import that produced it — the classic version of this
// bug is a review screen with its own idea of what a price is.

import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/models/models.dart';
import 'package:duka_pos/services/import_review_service.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:duka_pos/utils/units.dart';
import 'package:duka_pos/services/import_row_parser.dart';

ImportNeedsAttention problem(List<dynamic> row) => ImportNeedsAttention(
      source: 'excel',
      sheetName: 'Inventory',
      rowNumber: 4,
      rawRow: '[${row.map((dynamic c) => '"${c ?? ''}"').join(',')}]',
      problem: 'No Cost price',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('a row the owner can finish', () {
    test('the draft pre-fills exactly what the import would have written', () {
      final draft = ImportReviewService.draftFromRow(
          <dynamic>['', 'Bond 7', '', '169', '250', '4']);

      expect(draft.name, 'Bond 7');
      // The import's own exact parser, not a second opinion about prices.
      expect(draft.costMinor, 16900);
      expect(draft.sellMinor, 25000);
      expect(draft.stockQty, 4);
      expect(draft.missing, isEmpty, reason: 'nothing is missing');
      expect(draft.isComplete, isTrue);
    });

    test('a row missing its cost price asks for exactly that', () {
      // The row that started all of this: a price cell the supplier left empty.
      final draft = ImportReviewService.draftFromRow(
          <dynamic>['', 'Bond 7', '', '', '250', '4']);

      expect(draft.name, 'Bond 7');
      expect(draft.sellMinor, 25000, reason: 'the price it DID say is kept');
      expect(draft.stockQty, 4);
      expect(draft.missing, <String>['cost']);
    });

    test('a row missing every price asks for all of them, and nothing more',
        () {
      final draft = ImportReviewService.draftFromRow(
          <dynamic>['', 'Balozi', '', '', '', '']);

      expect(draft.missing, <String>['cost', 'sell']);
      expect(draft.stockQty, ImportRowParser.defaultStockQty,
          reason: 'a blank stock is a supplier not counting the shelf');
    });

    test('a row with no name asks for a name', () {
      final draft =
          ImportReviewService.draftFromRow(<dynamic>['', '', '', '169', '250']);

      expect(draft.missing, contains('name'));
    });

    test('a price the sheet wrote is accepted in the form it was written', () {
      // "KSh 169", "1,200.50", ".5" — the same spellings the import accepts,
      // because it is the import's parser reading them.
      for (final MapEntry<String, int> entry in <MapEntry<String, int>>[
        const MapEntry<String, int>('KSh 169.00', 16900),
        const MapEntry<String, int>('1,200.50', 120050),
        const MapEntry<String, int>(' 250 ', 25000),
      ]) {
        final draft =
            ImportReviewService.draftFromRow(<dynamic>['', 'X', '', entry.key]);
        expect(draft.costMinor, entry.value, reason: entry.key);
      }
    });

    test('a complete draft writes a product the shop can sell', () {
      final draft = ImportReviewService.draftFromRow(
          <dynamic>['', 'Bond 7', '', '169', '250', '4']);

      final product = draft.toProduct()!;

      expect(product.name, 'Bond 7');
      expect(product.costPrice, Money.fromMinor(16900));
      expect(product.sellPrice, Money.fromMinor(25000));
      expect(product.stockQty, 4);
      expect(product.unit, ProductUnit.each,
          reason: 'a countable row imports as countable');
    });

    test('an incomplete draft writes nothing at all', () {
      // Null rather than a half-built product: a caller that ignored
      // `isComplete` and wrote this anyway would be the bug the importer
      // exists to stop.
      final draft =
          ImportReviewService.draftFromRow(<dynamic>['', 'Bond 7', '', '', '']);

      expect(draft.toProduct(), isNull);
    });

    test("a row's own category cell is what it keeps", () {
      // A supplier's SECTION title is a property of the file walk, not of the
      // row — a single row cannot know which title it sat under, so the review
      // takes the row's own cell and never invents one.
      final draft = ImportReviewService.draftFromRow(
          <dynamic>['', 'Bond 7', 'Spirits', '169', '250', '4']);

      expect(draft.category, 'Spirits');
      final product = draft.toProduct()!;
      expect(product.category, 'Spirits');
    });

    test('a row with no category is inferred from its name, as the import does',
        () {
      final draft = ImportReviewService.draftFromRow(
          <dynamic>['', 'Kenya Lager', '', '40.55', '60.25', '24']);

      expect(draft.toProduct()!.category, isNotEmpty);
    });
  });

  group('a row that cannot be read at all', () {
    test('unreadable JSON asks for everything rather than guessing', () {
      final broken = ImportNeedsAttention(
        source: 'excel',
        sheetName: 'Inventory',
        rowNumber: 4,
        rawRow: 'not json at all',
        problem: 'No Cost price',
        createdAt: DateTime(2026, 1, 1),
      );

      final draft = ImportReviewService.draftFrom(broken);

      expect(draft.missing, <String>['name', 'cost', 'sell']);
      expect(draft.toProduct(), isNull);
    });

    test('a stored row routes through the JSON the importer kept', () {
      // The real path: the draft is read from the stored `rawRow`, so the file
      // the owner sees is the row the import saw.
      final draft = ImportReviewService.draftFrom(
          problem(<dynamic>['', 'Kenya Lager', '', '40.55', '60.25', '24']));

      expect(draft.name, 'Kenya Lager');
      expect(draft.costMinor, 4055, reason: 'exact, not a float of it');
      expect(draft.sellMinor, 6025);
    });
  });
}
