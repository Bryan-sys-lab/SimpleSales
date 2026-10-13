/// The half of an import that touches the database.
///
/// Parsing lives in `import_row_parser.dart` and is pure; everything here is
/// about the three promises the old importer broke. It reported the number of
/// rows it *parsed* as the number *imported*, so a row dropped for a bad
/// barcode was counted as a success. It wrote products whose barcodes it then
/// refused, and it never recorded a single dropped row anywhere. Two importers
/// (Excel and Google Sheets) each had their own copy of this logic, which is how
/// they drifted into disagreeing about what "imported" meant.
library;

import '../db/database_helper.dart';
import '../models/models.dart';
import '../utils/money.dart';
import '../utils/units.dart';
import 'barcode/barcode_service.dart';
import 'import_row_parser.dart';

/// Tab names, shared by both importers.
///
/// The inventory tab is located by name rather than by position: a supplier
/// workbook whose first tab is a cover note or a `Sales` extract was previously
/// parsed as if it were the catalogue, and then reported one generic failure for
/// the whole file. The other two are optional — a workbook without them is a
/// workbook from before they existed, and must still import unchanged.
const String inventorySheetName = 'Inventory';
const String barcodesSheetName = 'Barcodes';
const String variantsSheetName = 'Variants';

/// A product row parsed and waiting to be written, with the row it came from.
///
/// The row number travels with the product because a row can still be flagged
/// *after* the write — a barcode that turns out to be unusable is discovered
/// then — and the flag has to point at the line in the owner's file.
class PendingProduct {
  const PendingProduct({
    required this.source,
    required this.sheetName,
    required this.rowNumber,
    required this.cells,
    required this.product,
  });

  final String source;
  final String sheetName;
  final int rowNumber;
  final List<dynamic> cells;
  final Product product;

  ImportRow asImportRow() => ImportRow(rowNumber, cells);
}

/// A variant read off the `Variants` sheet, not yet attached to a local product.
///
/// The sheet carries the *spreadsheet's* idea of which product a variant
/// belongs to, which is not necessarily an id that exists on this device: an
/// export from the shop's laptop and a freshly reinstalled till disagree about
/// ids while agreeing completely about the products themselves.
class PendingVariant {
  const PendingVariant({
    required this.rowNumber,
    required this.cells,
    required this.sheetProductId,
    required this.variantId,
    required this.name,
    this.sku = '',
    this.unit,
    this.sizeMl = 0,
    this.sellPrice,
    this.costPrice,
    this.stockQty = 0,
    this.reorderLevel = 0,
    this.problem,
  });

  final int rowNumber;
  final List<dynamic> cells;
  final int? sheetProductId;
  final int? variantId;
  final String name;
  final String sku;
  final ProductUnit? unit;
  final int sizeMl;
  final Money? sellPrice;
  final Money? costPrice;
  final double stockQty;
  final int reorderLevel;

  /// Set when the row itself is unusable; the variant is then never written.
  final String? problem;

  bool get isRejected => problem != null;
}

/// A code from the `Barcodes` sheet, not yet attached to a local product.
///
/// Same shape as [PendingVariant] and for the same reason: the sheet's
/// `product_id` is the *spreadsheet's* id, which is meaningless on a device that
/// never saw that workbook.
class PendingBarcode {
  const PendingBarcode({
    required this.rowNumber,
    required this.cells,
    required this.raw,
    this.sheetProductId,
    this.kind = BarcodeKind.supplier,
    this.problem,
  });

  final int rowNumber;
  final List<dynamic> cells;
  final int? sheetProductId;
  final String raw;
  final String kind;

  /// Set when the code itself is unusable, so it is never attached.
  final String? problem;

  bool get isRejected => problem != null;
}

/// One `Variants` row, in [ProductVariant.sheetHeaders] order.
///
/// Prices leave in whole shillings for the same reason [Product.toSheetRow]
/// writes them that way: this row is read and edited by people in a
/// spreadsheet, and a column of 4050 where a human expects 40.50 is silently
/// misread as a price. [ProductVariant.toMap] stores minor units, so the
/// conversion is made here rather than trusted to the caller.
List<dynamic> variantSheetRow(ProductVariant variant) {
  final values = variant.toMap();
  return [
    for (final header in ProductVariant.sheetHeaders)
      switch (header) {
        'sell_price' => variant.sellPrice.asMajor,
        'cost_price' => variant.costPrice.asMajor,
        _ => values[header],
      }
  ];
}

/// Reads the optional `Barcodes` sheet.
///
/// Pure like [readVariantRows], and for the same reason: a code is either
/// attached to the right product or it is a code that scans the wrong item at
/// the till, and a mis-mapped column produces exactly that with no error
/// anywhere.
List<PendingBarcode> readBarcodeRows(List<List<dynamic>> raw) {
  if (raw.isEmpty) return const [];
  final columns = _namedColumns(raw.first, ProductBarcode.sheetHeaders);
  final start = columns.headerRowDetected ? 1 : 0;
  final codes = <PendingBarcode>[];
  for (var i = start; i < raw.length; i++) {
    if (SheetColumns.isBlankRow(raw[i])) continue;
    final cells = raw[i];
    final raw0 = columns.text(cells, 'barcode') ?? '';
    final sheetProductId =
        SheetColumns.parseNumber(columns.cell(cells, 'product_id'))?.round();
    String? problem;
    if (raw0.isEmpty) {
      problem = 'Row has no barcode';
    } else if (sheetProductId == null) {
      problem = 'Barcode "$raw0" does not say which product it belongs to';
    } else {
      final normalised = Barcode.normalise(raw0);
      final rejection = normalised.isEmpty
          ? 'Enter a barcode'
          : Barcode.rejectionReason(normalised);
      if (rejection != null) problem = 'Barcode "$raw0" $rejection';
    }
    codes.add(PendingBarcode(
      rowNumber: i + 1,
      cells: cells,
      sheetProductId: sheetProductId,
      raw: raw0,
      kind: BarcodeKind.parse(columns.text(cells, 'kind')),
      problem: problem,
    ));
  }
  return codes;
}

/// Reads the optional `Variants` sheet into attachable variants.
///
/// Pure, and shared by both importers for the same reason the row parser is:
/// two copies of a column layout is how a variant's price ends up in the stock
/// column on one path and not the other. Nothing here touches the database —
/// attaching a variant to its product needs the local ids the write produces.
///
/// [fields] defaults to [ProductVariant.sheetHeaders] so the export and the
/// import can never drift apart, exactly as [ProductBarcode.sheetHeaders]
/// cannot drift from its own sheet.
List<PendingVariant> readVariantRows(
  List<List<dynamic>> raw, {
  List<String> fields = ProductVariant.sheetHeaders,
}) {
  if (raw.isEmpty) return const [];
  final columns = _variantColumns(raw.first, fields);
  final start = columns.headerRowDetected ? 1 : 0;
  final variants = <PendingVariant>[];
  for (var i = start; i < raw.length; i++) {
    if (SheetColumns.isBlankRow(raw[i])) continue;
    variants.add(_parseVariant(i + 1, raw[i], columns));
  }
  return variants;
}

/// Field names a supplier's extra sheets have used, beyond our own headers.
const Map<String, String> _extraSheetAliases = {
  'product': 'product_id',
  'parent': 'product_id',
  'variant': 'variant_id',
  'price': 'sell_price',
  'cost': 'cost_price',
  'size': 'size_ml',
  'serving': 'size_ml',
  'measure': 'unit',
  'code': 'barcode',
  'bar code': 'barcode',
  'type': 'kind',
};

/// Maps [header] onto [fields] by name, or falls back to positional when the row
/// does not name the fields.
SheetColumns _namedColumns(List<dynamic> header, List<String> fields) {
  final byName = {
    for (final field in fields) field: SheetColumns.normaliseHeader(field),
  };
  final map = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    final text = SheetColumns.normaliseHeader(header[i]?.toString() ?? '');
    if (text.isEmpty) continue;
    final field = byName[text] ?? _extraSheetAliases[text];
    if (field == null) continue;
    map.putIfAbsent(field, () => i);
  }
  return map.isEmpty
      ? SheetColumns.positionalFor(fields)
      : SheetColumns.named(map, headerRowDetected: true);
}

SheetColumns _variantColumns(List<dynamic> header, List<String> fields) =>
    _namedColumns(header, fields);

PendingVariant _parseVariant(int rowNumber, List<dynamic> row, SheetColumns c) {
  int? int_(String field) =>
      SheetColumns.parseNumber(c.cell(row, field))?.round();

  final name = c.text(row, 'name') ?? '';
  if (name.isEmpty) {
    return PendingVariant(
      rowNumber: rowNumber,
      cells: row,
      sheetProductId: null,
      variantId: null,
      name: '',
      problem: 'No variant name',
    );
  }

  final sellCell = c.cell(row, 'sell_price');
  final sell = SheetColumns.parseNumber(sellCell);
  if (sell == null) {
    final text = sellCell?.toString().trim() ?? '';
    return PendingVariant(
      rowNumber: rowNumber,
      cells: row,
      sheetProductId: int_('product_id'),
      variantId: int_('variant_id'),
      name: name,
      problem: text.isEmpty
          ? 'Variant "$name" has no selling price'
          : 'Variant "$name" selling price "$text" is not a number',
    );
  }

  final unit = ProductUnit.parse(c.text(row, 'unit'));
  final sizeCell = c.cell(row, 'size_ml');
  final sizeText = sizeCell?.toString().trim() ?? '';
  var sizeMl = 0;
  if (sizeText.isNotEmpty) {
    // Through Volume so a supplier writing "0.5" for a cup means half a litre.
    final volume = Volume.parse(sizeText, declared: unit);
    if (!volume.isValid) {
      return PendingVariant(
        rowNumber: rowNumber,
        cells: row,
        sheetProductId: int_('product_id'),
        variantId: int_('variant_id'),
        name: name,
        unit: unit,
        sellPrice: Money.fromMajor(sell),
        problem: 'Variant "$name" size "$sizeText" is not a size the app '
            'understands (try 500, "500ml" or "1.5 L")',
      );
    }
    sizeMl = volume.rounded;
  }

  return PendingVariant(
    rowNumber: rowNumber,
    cells: row,
    sheetProductId: int_('product_id'),
    variantId: int_('variant_id'),
    name: name,
    sku: c.text(row, 'sku') ?? '',
    unit: unit,
    sizeMl: sizeMl,
    sellPrice: Money.fromMajor(sell),
    costPrice: _money(c.cell(row, 'cost_price')),
    stockQty: SheetColumns.parseNumber(c.cell(row, 'stock_qty')) ?? 0,
    reorderLevel: int_('reorder_level') ?? 0,
  );
}

Money? _money(dynamic cell) {
  final value = SheetColumns.parseNumber(cell);
  return value == null ? null : Money.fromMajor(value);
}

/// Writes parsed rows and reports exactly what happened.
class InventoryImporter {
  InventoryImporter(this._db);

  final DatabaseHelper _db;

  /// Applies one import.
  ///
  /// [rows] are the data rows of the inventory sheet, in file order. [columns]
  /// decides how each row is read; see [SheetColumns]. Every row the owner
  /// should know about lands in `import_needs_attention` with its original
  /// values, whether or not it was written.
  Future<InventoryImportResult> apply({
    required String source,
    required String sheetName,
    required List<ImportRow> rows,
    SheetColumns? columns,
    List<PendingBarcode> barcodes = const [],
    List<PendingVariant> variants = const [],
    List<String> skippedSheets = const [],
  }) async {
    final cols = columns ?? SheetColumns.positional;
    var needsAttention = 0;

    // This import supersedes every problem the last import of this sheet left.
    // Without it the list only grows: re-importing a fixed file would keep the
    // rows the previous import failed on, and the dashboard would keep counting
    // them long after they had been dealt with. Resolved BEFORE any new problem
    // is recorded, so the list always describes this import and not its
    // predecessors.
    await _db.resolveImportProblemsForSheet(
        source: source, sheetName: sheetName);

    Future<void> flag(ImportRow row, String problem) async {
      needsAttention++;
      await _db.recordImportProblem(
        source: source,
        sheetName: sheetName,
        rowNumber: row.number,
        rawName: row.rawName(cols),
        rawRow: row.cells,
        problem: problem,
      );
    }

    final pending = <PendingProduct>[];
    for (final row in rows) {
      if (SheetColumns.isBlankRow(row.cells)) continue;
      final parsed = ImportRowParser.parseProductRow(row.cells,
          parseId: _parseId, columns: cols, section: row.section);
      if (parsed.needsAttention) await flag(row, parsed.problem!);
      final product = parsed.product;
      if (product != null) {
        pending.add(PendingProduct(
          source: source,
          sheetName: sheetName,
          rowNumber: row.number,
          cells: row.cells,
          product: product,
        ));
      }
    }

    // Registered before anything is written, so no product can land with a
    // category the shop's vocabulary has never heard of. The importer is the
    // only place that knows what this shop actually stocks.
    final categories = <String>{
      for (final entry in pending) entry.product.category
    };
    for (final category in categories) {
      await _db.ensureCategory(category);
    }

    final written = await _write(pending);

    final idByName = <String, int>{};
    if (written.entries.isNotEmpty) {
      for (final product in await _db.getProducts(activeOnly: false)) {
        idByName.putIfAbsent(product.name.toLowerCase(), () => product.id!);
      }
    }

    // A row's spreadsheet id means something only if that id already existed
    // here; otherwise this import created the product and it has to be found by
    // name. Getting this wrong attaches a barcode to the wrong product, which
    // scans the wrong item at the till — worse than not attaching it at all.
    int? resolveId(PendingProduct entry) {
      final id = entry.product.id;
      if (id != null && written.updatedIds.contains(id)) return id;
      return idByName[entry.product.name.toLowerCase()];
    }

    final localIdBySheetId = <int, int>{};
    final refusedBarcodes = <String, String>{};
    final codes = <ProductBarcode>[];
    for (final entry in written.entries) {
      final localId = resolveId(entry);
      final sheetId = entry.product.id;
      if (localId != null && sheetId != null) {
        localIdBySheetId[sheetId] = localId;
      }

      final raw = entry.product.primaryBarcode;
      if (raw == null || raw.trim().isEmpty) continue;
      final code = Barcode.normalise(raw);
      final rejection =
          code.isEmpty ? 'Enter a barcode' : Barcode.rejectionReason(code);
      if (rejection != null) {
        // The product is still written: it is the *code* that is unusable, and
        // dropping the whole product over one typo is the loss this importer
        // exists to prevent.
        await flag(entry.asImportRow(),
            'Barcode "$raw" $rejection — the product was imported without it');
        continue;
      }
      if (localId == null) continue;
      codes.add(ProductBarcode(barcode: code, productId: localId));
    }

    for (final pending in barcodes) {
      if (pending.isRejected) {
        needsAttention++;
        await _db.recordImportProblem(
          source: source,
          sheetName: barcodesSheetName,
          rowNumber: pending.rowNumber,
          rawName: pending.raw,
          rawRow: pending.cells,
          problem: pending.problem!,
        );
        continue;
      }
      final localId = localIdBySheetId[pending.sheetProductId!];
      if (localId == null) {
        // Refused rather than guessed at. A code attached to the wrong product is
        // a code that scans the wrong item at the till, which is worse than no
        // code at all — and the row is kept so the owner can fix the sheet.
        needsAttention++;
        await _db.recordImportProblem(
          source: source,
          sheetName: barcodesSheetName,
          rowNumber: pending.rowNumber,
          rawName: pending.raw,
          rawRow: pending.cells,
          problem:
              'Barcode "${pending.raw}" points at a product that is not in '
              'this import, so it was left alone',
        );
        continue;
      }
      codes.add(ProductBarcode(
        barcode: Barcode.normalise(pending.raw),
        productId: localId,
        kind: pending.kind,
      ));
    }

    for (final code in await _db.addBarcodes(codes)) {
      final owner = await _db.getProductOwningBarcode(code);
      refusedBarcodes[code] = owner?.name ?? 'another product';
    }

    needsAttention += await _writeVariants(
      source: source,
      sheetName: sheetName,
      variants: variants,
      localIdBySheetId: localIdBySheetId,
    );

    return InventoryImportResult(
      imported: written.entries.length,
      created: written.inserted,
      updated: written.updatedCount,
      needsAttention: needsAttention,
      refusedBarcodes: refusedBarcodes,
      skippedSheets: skippedSheets,
    );
  }

  Future<_WriteOutcome> _write(List<PendingProduct> pending) async {
    if (pending.isEmpty) {
      return const _WriteOutcome(
        entries: [],
        inserted: 0,
        updatedCount: 0,
        updatedIds: {},
      );
    }
    final products = pending.map((entry) => entry.product).toList();

    // "Updated" has to mean the row existed before this import. A workbook's id
    // column is a spreadsheet artefact: restoring onto a fresh device carries ids
    // that exist nowhere, and calling those "updated" would report forty updates
    // where forty products were in fact created.
    final knownIds = <int>{
      for (final product in await _db.getProducts(activeOnly: false))
        if (product.id != null) product.id!,
    };
    final updatedIds = <int>{
      for (final product in products)
        if (product.id != null && knownIds.contains(product.id)) product.id!,
    };

    // One transaction for the whole file first, because that is what makes a
    // large import fast and atomic. If it throws, the transaction rolled back
    // and nothing was written, so falling back to row-by-row loses nothing and
    // recovers the thirty-nine good rows a single bad row would otherwise cost.
    try {
      await _db.upsertProducts(products);
      return _WriteOutcome(
        entries: pending,
        inserted: products.length - updatedIds.length,
        updatedCount: updatedIds.length,
        updatedIds: updatedIds,
      );
    } catch (_) {
      final entries = <PendingProduct>[];
      var inserted = 0;
      var updatedCount = 0;
      for (final entry in pending) {
        try {
          await _db.upsertProduct(entry.product);
          entries.add(entry);
          if (entry.product.id != null &&
              updatedIds.contains(entry.product.id)) {
            updatedCount++;
          } else {
            inserted++;
          }
        } catch (error) {
          await _db.recordImportProblem(
            source: entry.source,
            sheetName: entry.sheetName,
            rowNumber: entry.rowNumber,
            rawName: entry.product.name,
            rawRow: entry.cells,
            problem: 'Could not be saved: $error',
          );
        }
      }
      return _WriteOutcome(
        entries: entries,
        inserted: inserted,
        updatedCount: updatedCount,
        updatedIds: updatedIds,
      );
    }
  }

  /// Attaches variants to the products this import wrote.
  ///
  /// A variant whose product is not in this file is refused rather than guessed
  /// at, and the refusal is recorded: a silently dropped variant is a price the
  /// till cannot charge and no report mentions.
  Future<int> _writeVariants({
    required String source,
    required String sheetName,
    required List<PendingVariant> variants,
    required Map<int, int> localIdBySheetId,
  }) async {
    if (variants.isEmpty) return 0;
    var flagged = 0;

    Future<void> flag(PendingVariant variant, String problem) async {
      flagged++;
      await _db.recordImportProblem(
        source: source,
        sheetName: sheetName,
        rowNumber: variant.rowNumber,
        rawName: variant.name,
        rawRow: variant.cells,
        problem: problem,
      );
    }

    // Matched on the name under the parent, so re-importing an edited workbook
    // updates variants instead of accumulating a second "Dark" every time.
    final existingByName = <String, int>{};
    for (final variant in await _db.getAllVariants()) {
      if (variant.id == null) continue;
      existingByName.putIfAbsent(
        '${variant.productId}:${variant.name.toLowerCase()}',
        () => variant.id!,
      );
    }

    for (final variant in variants) {
      if (variant.isRejected) {
        await flag(variant, variant.problem!);
        continue;
      }
      final sheetProductId = variant.sheetProductId;
      final localId =
          sheetProductId == null ? null : localIdBySheetId[sheetProductId];
      if (localId == null) {
        await flag(
          variant,
          'Variant "${variant.name}" points at a product that is not in this '
          'import, so it was left alone',
        );
        continue;
      }
      final sell = variant.sellPrice;
      if (sell == null) {
        await flag(
          variant,
          'Variant "${variant.name}" has no selling price, so it was left alone',
        );
        continue;
      }
      await _db.upsertVariant(ProductVariant(
        id: existingByName['$localId:${variant.name.toLowerCase()}'],
        productId: localId,
        name: variant.name,
        sku: variant.sku,
        unit: variant.unit ?? ProductUnit.each,
        sizeMl: variant.sizeMl,
        sellPrice: sell,
        costPrice: variant.costPrice ?? Money.zero,
        stockQty: variant.stockQty,
        reorderLevel: variant.reorderLevel,
        position: 0,
      ));
    }
    return flagged;
  }

  static int? _parseId(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString().trim());
  }
}

class _WriteOutcome {
  const _WriteOutcome({
    required this.entries,
    required this.inserted,
    required this.updatedCount,
    required this.updatedIds,
  });

  /// Rows confirmed written. This — not the number parsed — is what "imported"
  /// means.
  final List<PendingProduct> entries;

  final int inserted;
  final int updatedCount;
  final Set<int> updatedIds;
}

/// What one import applied, so the owner is told what actually happened.
///
/// A partial import is the normal outcome, not a failure: a supplier workbook
/// that reuses one barcode across two rows must not abort the whole file, and
/// "imported 40 products, refused 3 barcodes" is far more useful than an error.
///
/// Every figure counts something that actually happened. [imported] is rows
/// *written*, not rows read — the previous version reported the parsed count, so
/// a row dropped for an unusable barcode was counted as a success and the
/// owner's stock count quietly came out short.
class InventoryImportResult {
  const InventoryImportResult({
    required this.imported,
    this.created = 0,
    this.updated = 0,
    this.needsAttention = 0,
    this.refusedBarcodes = const {},
    this.skippedSheets = const [],
  });

  /// Rows written to the database.
  final int imported;

  /// Of those, how many did not exist here before.
  final int created;

  /// Of those, how many replaced an existing product.
  final int updated;

  /// Rows on the needs-attention list, whether or not they were written.
  ///
  /// Readable and resolvable from the owner's Imports screen. Every dropped row
  /// is in here; a dropped row that leaves no trace is a row that is gone.
  final int needsAttention;

  /// Codes already attached to another product, by product name.
  final Map<String, String> refusedBarcodes;

  /// Tabs in the workbook that were not imported, by name. A `Sales` tab in a
  /// supplier's file is not an error, but silently ignoring it leaves the owner
  /// wondering whether their 200 rows of sales came in.
  final List<String> skippedSheets;

  /// The old name for [imported].
  ///
  /// Kept so the screens that already read it keep compiling. It is exactly the
  /// number they were already showing, now counting writes rather than parses.
  int get products => imported;
}
