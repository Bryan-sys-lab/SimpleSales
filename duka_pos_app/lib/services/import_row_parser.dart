/// Reading a supplier's spreadsheet without ever throwing.
///
/// Every parse of untrusted input needs a *total* result type: each row either
/// yields a [Product] or a sentence explaining, in the owner's language, why it
/// did not. The previous parser called [Product.validate] and threw a
/// [FormatException] on the first bad cell, which aborted the whole workbook —
/// one mistyped price in row 2 of a 40-row file cost the owner all 40 products.
/// The bug class only ever shows up on the one file the owner actually needed,
/// which is exactly why the type forces the caller to handle it.
///
/// Three things this file deliberately does not do:
///  * It never decides whether a problem is fatal. [ImportProblem] says how
///    loudly to complain; the caller decides what to do with the row.
///  * It never touches the database. Categories are resolved here as pure
///    strings and registered by the importer.
///  * It never invents a price. An unparseable optional price rejects the row
///    rather than writing null over a price the shop had already set.
library;

import '../models/models.dart';
import '../utils/money.dart';
import '../utils/units.dart';

/// How badly one row went wrong.
///
/// [attention] still yields a usable [Product]: the row is written *and* the
/// owner is told, because the value we wrote is a stated default rather than
/// the supplier's number. [reject] yields no product at all, because writing one
/// would either fabricate a price or destroy a price already in the database.
enum ImportProblem {
  none,
  attention,
  reject,
}

/// The outcome of parsing one spreadsheet row.
///
/// [product] is non-null exactly when the row may be written, so there is no way
/// to accidentally persist a row the parser rejected. [problem] is the one
/// sentence shown to the owner and stored verbatim on the needs-attention row.
class ParsedRow {
  const ParsedRow({
    this.product,
    this.problem,
    this.severity = ImportProblem.none,
  });

  /// A row that imported cleanly.
  const ParsedRow.ok(Product this.product)
      : problem = null,
        severity = ImportProblem.none;

  /// A row that will be written, but whose value we had to guess.
  const ParsedRow.flagged(Product this.product, String this.problem)
      : severity = ImportProblem.attention;

  /// A row that will not be written. [product] is null and never will be.
  const ParsedRow.rejected(String this.problem)
      : product = null,
        severity = ImportProblem.reject;

  final Product? product;
  final String? problem;
  final ImportProblem severity;

  bool get isOk => severity == ImportProblem.none && product != null;

  /// True when the owner should be told about this row, whether or not it was
  /// written. Drives the `needsAttention` count in the import report.
  bool get needsAttention => severity != ImportProblem.none;

  bool get isRejected => severity == ImportProblem.reject;
}

/// One row of a sheet plus the spreadsheet row number the owner sees.
///
/// 1-based, header included, because "row 14" in the report has to mean row 14
/// in the file they are about to open and fix.
class ImportRow {
  const ImportRow(this.number, this.cells);

  final int number;
  final List<dynamic> cells;

  /// The product name as written, for the needs-attention list. Never parsed:
  /// the raw cell is what the owner needs to see, typo and all.
  String rawName([SheetColumns? columns]) {
    final cell = (columns ?? SheetColumns.positional).cell(cells, 'name');
    return cell?.toString().trim() ?? '';
  }
}

/// Which spreadsheet column holds which field.
///
/// A supplier's file is not this app's export format, and assuming a fixed
/// column order is how a workbook whose columns were dragged around silently
/// imported every price into the wrong field. When row 1 is recognisably a
/// header row, the names decide the mapping; otherwise the canonical order from
/// [Product.sheetHeaders] is used, which is what a header-less file means.
class SheetColumns {
  const SheetColumns._(this._indexByField, this.headerRowDetected);

  /// A mapping built by the caller, e.g. from a header row read by name.
  const SheetColumns.named(Map<String, int> indexByField,
      {this.headerRowDetected = false})
      : _indexByField = indexByField;

  final Map<String, int> _indexByField;

  /// Whether these positions came from a header row the caller has skipped.
  final bool headerRowDetected;

  bool get hasName => _indexByField.containsKey('name');

  /// The canonical column order, for a file with no recognisable header row.
  static final SheetColumns positional =
      SheetColumns.positionalFor(Product.sheetHeaders);

  /// The canonical order for any header list — [ProductVariant.sheetHeaders]
  /// for the `Variants` sheet, [Product.sheetHeaders] for `Inventory`.
  static SheetColumns positionalFor(List<String> fields) => SheetColumns._(
        {for (var i = 0; i < fields.length; i++) fields[i]: i},
        false,
      );

  /// Header spellings a real supplier file has used, mapped onto our fields.
  ///
  /// Matched on a lowercased, whitespace-collapsed, colon-stripped form. Kept
  /// deliberately small and boring: a header we cannot recognise falls back to
  /// the canonical position rather than being guessed at.
  static const Map<String, String> aliases = {
    'id': 'id',
    'product id': 'id',
    'name': 'name',
    'product name': 'name',
    'product': 'name',
    'item': 'name',
    'item name': 'name',
    'description': 'name',
    'category': 'category',
    'cat': 'category',
    'type': 'category',
    'cost_price': 'cost_price',
    'cost price': 'cost_price',
    'cost': 'cost_price',
    'buying price': 'cost_price',
    'buy price': 'cost_price',
    'purchase price': 'cost_price',
    'sell_price': 'sell_price',
    'sell price': 'sell_price',
    'selling price': 'sell_price',
    'sale price': 'sell_price',
    'price': 'sell_price',
    'retail price': 'sell_price',
    'stock_qty': 'stock_qty',
    'stock qty': 'stock_qty',
    'stock': 'stock_qty',
    'qty': 'stock_qty',
    'quantity': 'stock_qty',
    'on hand': 'stock_qty',
    'reorder_level': 'reorder_level',
    'reorder level': 'reorder_level',
    'reorder': 'reorder_level',
    'excise_stamp_batch': 'excise_stamp_batch',
    'excise stamp batch': 'excise_stamp_batch',
    'excise batch': 'excise_stamp_batch',
    'stamp batch': 'excise_stamp_batch',
    'excise': 'excise_stamp_batch',
    'bottle_ml': 'bottle_ml',
    'bottle ml': 'bottle_ml',
    'bottle size': 'bottle_ml',
    'size': 'bottle_ml',
    'size ml': 'bottle_ml',
    'size_ml': 'bottle_ml',
    'volume': 'bottle_ml',
    'ml': 'bottle_ml',
    'half_price': 'half_price',
    'half price': 'half_price',
    'half': 'half_price',
    'quarter_price': 'quarter_price',
    'quarter price': 'quarter_price',
    'quarter': 'quarter_price',
    'barcode': 'barcode',
    'bar code': 'barcode',
    'code': 'barcode',
    'ean': 'barcode',
    'unit': 'unit',
    'size unit': 'unit',
    'measure': 'unit',
    'measured in': 'unit',
  };

  /// `  Selling Price : ` and `SELLING PRICE` are the same header.
  static String normaliseHeader(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(':', '')
      .trim();

  int? indexOf(String field) => _indexByField[field];

  /// The cell holding [field], or null when the column is absent or the row is
  /// shorter than the column. Both are "the supplier did not give us this".
  dynamic cell(List<dynamic> row, String field) {
    final index = _indexByField[field];
    if (index == null || index < 0 || index >= row.length) return null;
    return row[index];
  }

  String? text(List<dynamic> row, String field) =>
      cell(row, field)?.toString().trim();

  /// True when row 1 is a header row rather than the shopkeeper's first product.
  ///
  /// Two independent signals, because either alone misfires. A single number in
  /// row 1 means data, whatever the words around it — a header row has no
  /// numbers in it. And a majority of the non-empty cells have to be names we
  /// recognise, so a first product row called "Blue Band 2pk" (whose words are
  /// not field names, and whose `2` is a number) is never mistaken for a header.
  static bool looksLikeHeaderRow(List<dynamic> row) {
    var considered = 0;
    var recognised = 0;
    for (final cell in row) {
      final text = cell?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      considered++;
      if (aliases.containsKey(normaliseHeader(text))) {
        recognised++;
      } else if (parseNumber(text) != null) {
        return false;
      }
    }
    if (considered == 0 || recognised == 0) return false;
    return recognised * 2 >= considered;
  }

  /// The mapping implied by [row], or null when it is not a header row.
  ///
  /// Null rather than a positional fallback so the caller can tell "this file has
  /// headers and I skipped them" from "this file has no headers and row 1 is a
  /// product", which is the difference between importing a file and quietly
  /// losing its first row.
  static SheetColumns? fromHeaderRow(List<dynamic> row) {
    if (!looksLikeHeaderRow(row)) return null;
    final map = <String, int>{};
    for (var i = 0; i < row.length; i++) {
      final field = aliases[normaliseHeader(row[i]?.toString() ?? '')];
      if (field == null) continue;
      // First wins: a duplicated header is a supplier's typo, and the leftmost
      // column is the one they filled in.
      map.putIfAbsent(field, () => i);
    }
    // A header row with no name column is not our format. Falling back to the
    // canonical order here would read some other column as the product name.
    if (!map.containsKey('name')) return null;
    return SheetColumns._(map, true);
  }

  /// The `1,200.50` / `KSh 40` / ` 12 ` spellings a supplier's file contains.
  ///
  /// A comma is only a thousands separator when the value *is* grouped
  /// (`1,200.50` yes, `12,50` no), because guessing on the ambiguous form turns
  /// a mistyped price into a price nobody typed. Anything still unparseable
  /// returns null, which the caller reports rather than defaults.
  static final RegExp _groupedNumber = RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$');
  static final RegExp _currency = RegExp(
    r'^(kes|ksh|ks|sh)\s*|\s*(kes|ksh)$',
    caseSensitive: false,
  );

  static double? parseNumber(dynamic cell) {
    if (cell == null) return null;
    if (cell is num) return cell.isFinite ? cell.toDouble() : null;
    var text = cell.toString().trim();
    if (text.isEmpty) return null;
    text = text.replaceAll(_currency, '').trim();
    if (text.isEmpty) return null;
    if (_groupedNumber.hasMatch(text)) text = text.replaceAll(',', '');
    final value = double.tryParse(text);
    return value != null && value.isFinite ? value : null;
  }

  /// A row with nothing in it. Not a row, so not an error, so not a
  /// needs-attention entry — a trailing blank line must not fill the list the
  /// owner has to work through.
  static bool isBlankRow(List<dynamic> row) {
    for (final cell in row) {
      if (cell == null) continue;
      if (cell is String && cell.trim().isEmpty) continue;
      return false;
    }
    return true;
  }
}

/// A whole sheet: its rows, and the column mapping they were read with.
///
/// The header decision lives here rather than in either importer because it is
/// the single most destructive thing either of them used to assume. `skip(1)`
/// was unconditional, so a header-less supplier file lost its first product —
/// and lost it silently, because a file that starts with a product has nothing
/// about it that looks like an error.
class SheetLayout {
  const SheetLayout({
    required this.columns,
    required this.rows,
    this.headerRow,
  });

  final SheetColumns columns;

  /// Data rows only, already stripped of the header when there was one.
  final List<ImportRow> rows;

  /// The header cells, when row 1 was one. Null for a header-less file.
  final List<dynamic>? headerRow;

  bool get headerRowDetected => columns.headerRowDetected;

  /// Decides whether [raw]'s first row is a header, and drops it if so.
  static SheetLayout fromRawRows(List<List<dynamic>> raw) {
    if (raw.isEmpty) {
      return SheetLayout(
        columns: SheetColumns.positional,
        rows: const [],
        headerRow: null,
      );
    }
    final first = raw.first;
    final detected = SheetColumns.fromHeaderRow(first);
    final columns = detected ?? SheetColumns.positional;
    final start = detected == null ? 0 : 1;
    final rows = <ImportRow>[
      for (var i = start; i < raw.length; i++) ImportRow(i + 1, raw[i]),
    ];
    return SheetLayout(
      columns: columns,
      rows: rows,
      headerRow: detected == null ? null : List<dynamic>.of(first),
    );
  }
}

/// Parses supplier rows into products, and only ever returns.
class ImportRowParser {
  const ImportRowParser._();

  /// Stock default for a row that did not say.
  ///
  /// Zero rather than a guess: stock is the one number here where a wrong value
  /// quietly corrupts a stock report and where zero is a safe, visible state
  /// (everything shows as low) instead of a plausible lie.
  static const double defaultStockQty = 0;

  /// Reorder level for a row that did not say.
  ///
  /// Five bottles: enough to trigger a reorder before the shelf is empty, and
  /// low enough that the prompt is not noise.
  static const int defaultReorderLevel = 5;

  /// Serving size used when the row is a countable item with no size given.
  ///
  /// Only safe because a countable product's portions are counted, not poured —
  /// see the volumetric branch below, which refuses rather than guesses.
  static const int defaultBottleMl = 750;

  /// The single entry point every importer goes through.
  ///
  /// [columns] decides where each value is read from; omit it for a file in this
  /// app's own export order. [parseId] converts the id column, which is a
  /// spreadsheet artefact rather than something we can trust to exist locally.
  static ParsedRow parseProductRow(
    List<dynamic> row, {
    int? Function(dynamic)? parseId,
    SheetColumns? columns,
  }) {
    final cols = columns ?? SheetColumns.positional;

    // Required. A row with no name is not a product, and inventing one ("Untitled
    // 7") fills the catalogue with rows the owner then has to delete.
    //
    // Trimmed *before* the check. A supplier sheet pads its name column with
    // spaces constantly, and `'	 	'` is not an empty cell to a human but is
    // non-empty as a string — so an untrimmed check writes a product whose name
    // renders as blank in the catalogue.
    final name = (cols.text(row, 'name') ?? '').trim();
    if (name.isEmpty) return const ParsedRow.rejected('No product name');

    // Required. Cost and selling price are the only two numbers a product
    // cannot exist without: a shop that stocks something at no price, or for no
    // cost, has not told us what it sells for. Defaulting either one fabricates
    // the single most consequential figure in the app.
    final costCell = cols.cell(row, 'cost_price');
    final cost = SheetColumns.parseNumber(costCell);
    if (cost == null) {
      return ParsedRow.rejected(_missingNumber('Cost price', costCell));
    }

    final sellCell = cols.cell(row, 'sell_price');
    final sell = SheetColumns.parseNumber(sellCell);
    if (sell == null) {
      return ParsedRow.rejected(_missingNumber('Selling price', sellCell));
    }

    String? warning;

    // Optional, defaulted, and never guessed into the report. A blank stock cell
    // is a supplier not counting the shelf, not a claim that it is empty, so it
    // is not worth an entry on the owner's list.
    final stockCell = cols.cell(row, 'stock_qty');
    final stock = SheetColumns.parseNumber(stockCell);
    if (stock == null) {
      final text = stockCell?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        warning = 'Stock quantity "$text" is not a number — imported as 0';
      }
    }

    final reorderCell = cols.cell(row, 'reorder_level');
    final reorderRaw = SheetColumns.parseNumber(reorderCell);
    final reorder = reorderRaw?.round() ?? defaultReorderLevel;
    if (reorderRaw == null) {
      final text = reorderCell?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        warning ??=
            'Reorder level "$text" is not a number — imported as $defaultReorderLevel';
      }
    }

    final unitCell = cols.text(row, 'unit') ?? '';
    final unit = ProductUnit.parse(unitCell);
    if (unitCell.isNotEmpty && !isKnownUnit(unitCell)) {
      warning ??=
          'Unit "$unitCell" was not recognised — imported as a countable item';
    }

    // Volume, not a bare number. "750", "0.75", "1.5 L" and "500ml" are all real
    // supplier spellings, and reading a tank as 750 millilitres is a
    // factor-of-two stock error that nobody sees until the month-end count.
    final sizeCell = cols.cell(row, 'bottle_ml');
    final sizeText = sizeCell?.toString().trim() ?? '';
    late final int bottleMl;
    if (sizeText.isEmpty) {
      if (unit.isVolumetric) {
        // The row says it is sold by volume and gives no volume. Any number we
        // wrote here would be invented, so the row waits for the owner.
        return ParsedRow.rejected(
          'No bottle size — the row says it is measured in ${unit.suffix}, '
          'so the size cannot be guessed',
        );
      }
      bottleMl = defaultBottleMl;
      warning ??= 'No bottle size — imported as $defaultBottleMl ml';
    } else {
      final volume = Volume.parse(sizeText, declared: unit);
      if (!volume.isValid) {
        return ParsedRow.rejected(
          'Bottle size "$sizeText" is not a size the app understands '
          '(try 750, "500ml" or "1.5 L")',
        );
      }
      bottleMl = volume.rounded;
    }

    // Optional prices. The asymmetry is the whole point: an EMPTY cell means
    // "not sold in portions" and stays null, but a cell holding something that
    // is not a number is rejected. Writing null over `half_price = 25` destroys
    // a real price the shop had set and silently changes what the till charges.
    final halfCell = cols.cell(row, 'half_price');
    final half = SheetColumns.parseNumber(halfCell);
    final halfText = halfCell?.toString().trim() ?? '';
    if (half == null && halfText.isNotEmpty) {
      return ParsedRow.rejected(
        'Half price "$halfText" is not a number — the row was left out so the '
        'price already on this product is kept',
      );
    }

    final quarterCell = cols.cell(row, 'quarter_price');
    final quarter = SheetColumns.parseNumber(quarterCell);
    final quarterText = quarterCell?.toString().trim() ?? '';
    if (quarter == null && quarterText.isNotEmpty) {
      return ParsedRow.rejected(
        'Quarter price "$quarterText" is not a number — the row was left out so '
        'the price already on this product is kept',
      );
    }

    final category = resolveCategory(cols.text(row, 'category'), name);

    // The shared validator, so an imported row can never hold a value the editor
    // would refuse to save: over-long names, negative stock, absurd sizes.
    final invalid = Product.validate(
      name: name,
      category: category,
      costPrice: cost,
      sellPrice: sell,
      stockQty: stock ?? defaultStockQty,
      reorderLevel: reorder,
      bottleMl: bottleMl,
      halfPrice: half,
      quarterPrice: quarter,
    );
    if (invalid != null) return ParsedRow.rejected(invalid);

    final barcode = cols.text(row, 'barcode') ?? '';
    final product = Product(
      id: parseId == null ? null : parseId(cols.cell(row, 'id')),
      name: name,
      category: category,
      costPrice: Money.fromMajor(cost),
      sellPrice: Money.fromMajor(sell),
      stockQty: stock ?? defaultStockQty,
      reorderLevel: reorder,
      bottleMl: bottleMl,
      unit: unit,
      halfPrice: half == null ? null : Money.fromMajor(half),
      quarterPrice: quarter == null ? null : Money.fromMajor(quarter),
      exciseStampBatch: cols.text(row, 'excise_stamp_batch') ?? '',
      updatedAt: DateTime.now().toIso8601String(),
      // Carried on the row so the importer can attach it to the product it just
      // wrote. Validated by the importer, which owns the database and is the only
      // place a duplicate can actually be enforced.
      primaryBarcode: barcode.isEmpty ? null : barcode,
    );
    return warning == null
        ? ParsedRow.ok(product)
        : ParsedRow.flagged(product, warning);
  }

  static bool isKnownUnit(String raw) {
    final value = raw.trim().toLowerCase();
    for (final unit in ProductUnit.values) {
      if (unit.wire == value ||
          unit.suffix == value ||
          unit.name.toLowerCase() == value ||
          unit.label.toLowerCase() == value) {
        return true;
      }
    }
    return false;
  }

  static String _missingNumber(String field, dynamic cell) {
    final text = cell?.toString().trim() ?? '';
    return text.isEmpty ? 'No $field' : '$field "$text" is not a number';
  }

  /// The category this row should be filed under.
  ///
  /// Normalised rather than copied: a supplier file containing `drinks`,
  /// `Drinks` and `Drinks ` used to produce three categories and three separate
  /// reports, which is worse than having no categories at all. An empty cell is
  /// inferred from the product name, because "Kenya Lager" filed under General
  /// is a row the owner has to re-file by hand, every time, forever.
  static String resolveCategory(String? raw, String productName) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) {
      return inferCategoryFromName(productName) ?? CategoryName.general;
    }
    return CategoryName.normalise(text);
  }

  /// The seed category a product *name* points at, or null when nothing matches.
  ///
  /// One pure function, deliberately: category guessing that lives in two
  /// importers is how the Excel path files a lager under Beer and the Sheets
  /// path files it under General, and neither report looks wrong on its own.
  /// Keywords are keyed by the seed list itself, so a shop that adds a seed
  /// gets matching behaviour for it without touching this function.
  static const Map<String, List<String>> keywordsBySeed = {
    'Beer': [
      'beer',
      'lager',
      'stout',
      'ale',
      'pilsner',
      'weiss',
      'kwalale',
      'tusker',
      'guinness',
      'sentinel',
      'chang',
      'castle',
      'white cap',
      'baridi',
    ],
    'Wines & Spirits': [
      'wine',
      'spirit',
      'whisky',
      'whiskey',
      'vodka',
      'gin',
      'rum',
      'cognac',
      'brand',
      'sherry',
      'kwale',
      'court',
    ],
    'Soft Drinks': [
      'soft drink',
      'soda',
      'coke',
      'coca cola',
      'fanta',
      'sprite',
      'pepsi',
      'mirinda',
      'kepo',
      'schweppes',
      'royal',
      'merry',
      'vimto',
    ],
    'Water': ['water', 'safi'],
    'Juice': ['juice', 'delice', 'tropicana', 'orangina', 'ribena', 'mango'],
    'Milk & Dairy': [
      'milk',
      'dairy',
      'yoghurt',
      'yogurt',
      'cheese',
      'butter',
      'cream',
      'maziwa',
      'mala',
    ],
    'Groceries': [
      'rice',
      'sugar',
      'cooking oil',
      'flour',
      'maize',
      'salt',
      'beans',
      'grocery',
      'pilchard',
    ],
    'Bakery': [
      'bread',
      'cake',
      'pastry',
      'croissant',
      'samosa',
      'mandazi',
      'loaf'
    ],
    'Produce': [
      'onion',
      'tomato',
      'potato',
      'banana',
      'vegetable',
      'fruit',
      'spinach',
      'kale',
      'cabbage',
      'sukuma',
    ],
    'Meat & Fish': [
      'meat',
      'chicken',
      'fish',
      'beef',
      'pork',
      'mutton',
      'nyama',
      'sausage',
      'sardine',
    ],
    'Household': [
      'detergent',
      'bleach',
      'phenyl',
      'tissue',
      'toilet roll',
      'cleaner',
      'soap',
      'matchbox',
      'dustbin',
    ],
    'Personal Care': [
      'shampoo',
      'toothpaste',
      'deodorant',
      'sanitary',
      'lotion',
      'razor',
      'baby powder',
    ],
    'Snacks': [
      'biscuit',
      'crisps',
      'nuts',
      'snack',
      'sweets',
      'chocolate',
      'cookies',
      'popcorn',
      // Brand names, because a supplier's price list writes "Sultani 300g" and
      // "Lays 70g", not "snacks". Without these the two most common Kenyan
      // snack lines both fall through to General, and the owner's snack report
      // is empty while their shelf is full.
      'sultani',
      'lays',
      'kurkure',
      'blackjack',
      'choclips',
      'pocky',
      'twisties',
      'clovers',
      'eclipse',
      'mentos',
      'ovaltine',
      'cadbury',
      'rituals',
    ],
    'Cigarettes & Tobacco': ['cigarette', 'tobacco', 'senzu', 'kibaki', 'roll'],
    'Stationery': [
      'exercise book',
      'pencil',
      'biro',
      'pen ',
      'ruler',
      'notebook',
      'crayon',
      'eraser',
    ],
  };

  /// The category whose keywords appear in [name], or null.
  ///
  /// Iterates [CategoryName.seeds] order so the answer does not depend on the
  /// order of the keyword map: a name that matches two seeds is filed under the
  /// one the shop lists first. A seed's own name is also matched as a
  /// substring, so "Household Cleaner 1L" lands in Household even without a
  /// keyword for "Cleaner".
  static String? inferCategoryFromName(String name) {
    final haystack =
        ' ${name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim()} ';
    if (haystack.trim().isEmpty) return null;

    for (final seed in CategoryName.seeds) {
      if (seed == CategoryName.general || seed == 'Other') continue;
      for (final keyword in keywordsBySeed[seed] ?? const <String>[]) {
        if (haystack.contains(keyword)) return seed;
      }
      // The seed's own words, with the connective dropped: "Meat & Fish" also
      // answers to "meat" and "fish" on its own.
      for (final word in seed
          .replaceAll('&', ' ')
          .toLowerCase()
          .split(' ')
          .where((word) => word.length > 2)) {
        if (haystack.contains(word)) return seed;
      }
    }
    return null;
  }
}
