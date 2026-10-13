// Completing the rows an import asked about.
//
// A row that arrives missing a price is not a row that should vanish. The
// importer refuses to invent the single most consequential figure in the app,
// so it keeps the row on the needs-attention list with its original values —
// and until now that list was a dead end. The dashboard said "re-import the
// spreadsheet to finish that update" for a file the owner had already fixed or
// could never fix, and nothing in the app let them answer.
//
// This is the answer, and it is a pure function of the stored row for a reason:
// what the draft pre-fills is exactly what the import would have written, and
// what it reports missing is exactly what the import refused on. Both go
// through the same parsers, so a draft can never disagree with the import that
// produced it — the classic version of this bug is a review screen with its own
// idea of what a price is.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../utils/money.dart';
import 'import_row_parser.dart';

/// What a problem row already gives us, and what it still needs.
///
/// [missing] names the fields the owner must fill, in the order the form shows
/// them. Everything else is pre-filled from the file and still editable: an
/// owner should be able to correct a stock count while they are there.
@immutable
class ImportDraft {
  const ImportDraft({
    required this.name,
    required this.costMinor,
    required this.sellMinor,
    required this.stockQty,
    required this.category,
    required this.reorderLevel,
    required this.missing,
  });

  /// The draft of a row that had nothing usable in it.
  const ImportDraft.empty()
      : name = '',
        costMinor = null,
        sellMinor = null,
        stockQty = ImportRowParser.defaultStockQty,
        category = '',
        reorderLevel = ImportRowParser.defaultReorderLevel,
        missing = const <String>['name', 'cost', 'sell'];

  final String name;
  final int? costMinor;
  final int? sellMinor;
  final double stockQty;
  final String category;
  final int reorderLevel;

  /// Which of name / cost / sell the owner still has to provide.
  final List<String> missing;

  bool get isComplete => missing.isEmpty;

  /// The product this draft writes, or null while [isComplete] is false.
  ///
  /// Null rather than a half-built product: a caller that ignored [isComplete]
  /// and wrote this anyway would be the bug the importer was written to stop.
  Product? toProduct() {
    if (!isComplete) return null;
    final cost = costMinor;
    final sell = sellMinor;
    if (cost == null || sell == null) return null;
    return Product(
      name: name.trim(),
      category: category.trim().isEmpty
          ? ImportRowParser.inferCategoryFromName(name) ?? CategoryName.general
          : CategoryName.normalise(category),
      costPrice: Money.fromMinor(cost),
      sellPrice: Money.fromMinor(sell),
      stockQty: stockQty,
      reorderLevel: reorderLevel,
      bottleMl: ImportRowParser.defaultBottleMl,
      updatedAt: DateTime.now().toIso8601String(),
    );
  }
}

/// Reads a problem row back into a draft the owner can finish.
///
/// Throws nothing. A row whose JSON cannot be decoded is an empty draft — the
/// owner is asked for everything, which is the only honest answer for a row
/// whose original values cannot be read at all.
class ImportReviewService {
  const ImportReviewService._();

  /// [problem] is the stored needs-attention entry; its `rawRow` is the JSON of
  /// the spreadsheet row the import was looking at.
  static ImportDraft draftFrom(ImportNeedsAttention problem) {
    final List<dynamic> row;
    try {
      final decoded = jsonDecode(problem.rawRow);
      row = decoded is List ? decoded : const <dynamic>[];
    } on FormatException {
      return const ImportDraft.empty();
    }
    return draftFromRow(row);
  }

  /// The same, from the row itself — which is what a test drives.
  ///
  /// The category comes from the row's own cell only. A supplier's SECTION
  /// title is a property of the file walk — it is whichever title the importer
  /// had last seen above this row — and a single row cannot know it, so guessing
  /// it here would file the finished product somewhere the import never would
  /// have. A row with no category of its own is inferred from its name, the same
  /// fallback the import uses.
  static ImportDraft draftFromRow(List<dynamic> row) {
    final SheetColumns columns = SheetColumns.positional;

    final name = (columns.text(row, 'name') ?? '').trim();
    final costMinor =
        SheetColumns.parseMinorUnits(columns.cell(row, 'cost_price'));
    final sellMinor =
        SheetColumns.parseMinorUnits(columns.cell(row, 'sell_price'));
    final stock = SheetColumns.parseNumber(columns.cell(row, 'stock_qty'));
    final reorderRaw =
        SheetColumns.parseNumber(columns.cell(row, 'reorder_level'));
    final category = (columns.text(row, 'category') ?? '').trim();

    final missing = <String>[
      if (name.isEmpty) 'name',
      if (costMinor == null) 'cost',
      if (sellMinor == null) 'sell',
    ];

    return ImportDraft(
      name: name,
      costMinor: costMinor,
      sellMinor: sellMinor,
      stockQty: stock ?? ImportRowParser.defaultStockQty,
      category: category,
      reorderLevel: reorderRaw?.round() ?? ImportRowParser.defaultReorderLevel,
      missing: missing,
    );
  }
}
