/// Core data models. Kept as plain classes with toMap/fromMap so they map
/// directly onto SQLite rows (see db/database_helper.dart) and onto
/// spreadsheet rows (see services/sheets_service.dart, services/excel_service.dart) —
/// one shape used everywhere avoids three slightly different versions drifting apart.
library;

import '../services/import_row_parser.dart';
import '../utils/money.dart';
import '../utils/units.dart';

class Owner {
  final int id;
  final String name;
  final String pinHash;
  final String email;
  final String shopName;
  final String createdAt;

  Owner({
    required this.id,
    required this.name,
    required this.pinHash,
    this.email = '',
    required this.shopName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'pin_hash': pinHash,
        'email': email,
        'shop_name': shopName,
        'created_at': createdAt,
      };

  factory Owner.fromMap(Map<String, dynamic> m) => Owner(
        id: m['id'],
        name: m['name'],
        pinHash: m['pin_hash'],
        email: (m['email'] as String?) ?? '',
        shopName: m['shop_name'],
        createdAt: m['created_at'],
      );
}

class Staff {
  final int? id;
  final String name;
  final String? username;
  final String pinHash;
  final bool active;
  final String? remoteId;
  final String role;

  Staff(
      {this.id,
      required this.name,
      this.username,
      required this.pinHash,
      this.active = true,
      this.remoteId,
      this.role = 'cashier'});

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        if (username != null) 'username': username,
        'pin_hash': pinHash,
        'active': active ? 1 : 0,
        'remote_id': remoteId,
        'role': role,
      };

  factory Staff.fromMap(Map<String, dynamic> m) => Staff(
        id: m['id'],
        name: m['name'],
        username: m['username'] as String?,
        pinHash: m['pin_hash'],
        active: m['active'] == 1,
        remoteId: m['remote_id'],
        role: m['role'] ?? 'cashier',
      );
}

/// Which rule of [Product.validate] a value broke.
///
/// The validator used to answer with a sentence, on the assumption that every
/// caller would build its own message anyway — until the imports screen showed
/// it verbatim and a shop on a non-English locale got English. A code travels
/// through the model layer; the importer turns it back into English with
/// [describe] (a stored row is data, written once and read later), and the
/// screens turn it into the shop's own language.
enum ProductProblem {
  name,
  nameTooLong,
  categoryTooLong,
  costPrice,
  sellPrice,
  stockQty,
  reorderLevel,
  size,
  halfPrice,
  quarterPrice;

  /// The stored-row sentence: what an import wrote, and what the owner's
  /// imports list shows.
  String describe() {
    switch (this) {
      case ProductProblem.name:
        return 'Enter a product name';
      case ProductProblem.nameTooLong:
        return 'Product name must be ${Product.maxNameLength} characters or '
            'fewer';
      case ProductProblem.categoryTooLong:
        return 'Category must be ${Product.maxCategoryLength} characters or '
            'fewer';
      case ProductProblem.costPrice:
        return 'Cost price must be a valid amount of 0 or more';
      case ProductProblem.sellPrice:
        return 'Selling price must be a valid amount of 0 or more';
      case ProductProblem.stockQty:
        return 'Stock quantity must be 0 or more';
      case ProductProblem.reorderLevel:
        return 'Reorder level must be 0 or more';
      case ProductProblem.size:
        return 'Size must be between ${Product.minBottleMl} and '
            '${Product.maxBottleMl} ml (a 50-litre keg is 50000)';
      case ProductProblem.halfPrice:
        return 'Half price must be a valid amount of 0 or more';
      case ProductProblem.quarterPrice:
        return 'Quarter price must be a valid amount of 0 or more';
    }
  }
}

class Product {
  final int? id;
  final String name;
  final String category;
  final Money costPrice;
  final Money sellPrice;
  final double stockQty;
  final int reorderLevel;
  final int bottleMl;

  /// What this product is measured in. A countable bottle is [ProductUnit.each]
  /// with a [bottleMl] size; something sold by the cup is [ProductUnit.cup] with
  /// the same size field holding the cup's volume.
  final ProductUnit unit;

  /// How many millilitres one kilogram of this product is.
  ///
  /// A TANK is stocked by weight and sold by the cup, and this is the bridge:
  /// `kg x this` is the millilitres the app counts and pours. [bottleMl] then
  /// holds the tank's capacity in those millilitres, exactly as it does for a
  /// keg measured in litres, so nothing downstream — the pour maths, the cups
  /// this tank holds, the low-stock threshold — needs to know the stock arrived
  /// on a scale.
  ///
  /// 0 for everything that is not stocked by weight, which is what makes a
  /// litre product's row and a tank's row distinguishable without a second flag:
  /// `unit.isMeasuredByWeight` and this is positive, or neither is.
  final double millilitresPerKilogram;

  /// Whether this product is sold as variants.
  ///
  /// Separate from "has variants" because the two mean different things to the
  /// owner: "has none" is a statement about the catalogue, "has not added them
  /// yet" is a prompt on the product itself.
  final bool trackVariants;
  final Money? halfPrice;
  final Money? quarterPrice;
  final String exciseStampBatch;
  final bool active;
  final String updatedAt;
  final String?
      remoteId; // Supabase products.id, once synced — see backend_service.dart

  /// Where this product's photograph lives, relative to the documents directory.
  ///
  /// A PATH and not the bytes: a photograph is the one large thing on a product
  /// row, and storing the bytes would put them in every encrypted backup and
  /// every cross-shop read. It is RELATIVE because the absolute directory
  /// differs between phones, so a backup restored onto a different handset
  /// resolves it against that handset's own directory — and yields null rather
  /// than a broken path when the files were not part of the backup.
  ///
  /// Read and drawn on the SELL screen only. Everywhere else a product is a row
  /// in a list, and a photograph there would make the list slower to scan and
  /// slower to render for no gain the owner asked for.
  final String? imagePath;

  /// The primary barcode, carried through a spreadsheet import only.
  ///
  /// Deliberately *not* persisted on this model: barcodes live in their own
  /// table with their own API (see [ProductBarcode]), and a product carrying a
  /// barcode field again is how the two start disagreeing. This is the
  /// transient hand-off between "read a row" and "write the codes".
  final String? primaryBarcode;

  Product({
    this.id,
    required this.name,
    required this.category,
    required this.costPrice,
    required this.sellPrice,
    required this.stockQty,
    required this.reorderLevel,
    this.bottleMl = 750,
    this.unit = ProductUnit.each,
    this.trackVariants = false,
    this.halfPrice,
    this.quarterPrice,
    this.exciseStampBatch = '',
    this.millilitresPerKilogram = 0,
    this.active = true,
    required this.updatedAt,
    this.remoteId,
    this.imagePath,
    this.primaryBarcode,
  });

  /// Computed from minor units so the ratio does not inherit float error from
  /// the two prices. Percentages are for display, so the final division to a
  /// double is expected and harmless.
  double get marginPct => sellPrice.isZero
      ? 0
      : ((sellPrice.minorUnits - costPrice.minorUnits) / sellPrice.minorUnits) *
          100;
  bool get isLow => stockQty <= reorderLevel;

  /// The price charged for one portion of a bottle.
  ///
  /// Derived portions divide money, so the split goes through [Money.times] and
  /// is quantised once. An odd-cent price therefore rounds to the nearest cent
  /// (half of KSh 10.01 is KSh 5.01) instead of leaking a fraction into the
  /// cart that could never be charged.
  Money priceFor(String portion) => portion == 'half'
      ? (halfPrice ?? sellPrice.times(0.5))
      : portion == 'quarter'
          ? (quarterPrice ?? sellPrice.times(0.25))
          : sellPrice;
  double fractionFor(String portion) => portion == 'half'
      ? 0.5
      : portion == 'quarter'
          ? 0.25
          : 1;
  int mlFor(String portion) => (bottleMl * fractionFor(portion)).round();

  Product copyWith({
    String? name,
    String? category,
    Money? costPrice,
    Money? sellPrice,
    double? stockQty,
    int? reorderLevel,
    int? bottleMl,
    Money? halfPrice,
    Money? quarterPrice,
    String? exciseStampBatch,
    bool? active,
    String? remoteId,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        costPrice: costPrice ?? this.costPrice,
        sellPrice: sellPrice ?? this.sellPrice,
        stockQty: stockQty ?? this.stockQty,
        reorderLevel: reorderLevel ?? this.reorderLevel,
        bottleMl: bottleMl ?? this.bottleMl,
        halfPrice: halfPrice ?? this.halfPrice,
        quarterPrice: quarterPrice ?? this.quarterPrice,
        exciseStampBatch: exciseStampBatch ?? this.exciseStampBatch,
        active: active ?? this.active,
        updatedAt: DateTime.now().toIso8601String(),
        remoteId: remoteId ?? this.remoteId,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'category': category,
        // Amounts are persisted as integer cents, never as REAL shillings.
        'cost_price': costPrice.minorUnits,
        'sell_price': sellPrice.minorUnits,
        'stock_qty': stockQty,
        'reorder_level': reorderLevel,
        'bottle_ml': bottleMl,
        'unit': unit.wire,
        'track_variants': trackVariants ? 1 : 0,
        // 0 for a product not stocked by weight; see the field's doc.
        'ml_per_kg': millilitresPerKilogram,
        'half_price': halfPrice?.minorUnits,
        'quarter_price': quarterPrice?.minorUnits,
        'excise_stamp_batch': exciseStampBatch,
        'active': active ? 1 : 0,
        'updated_at': updatedAt,
        'remote_id': remoteId,
        'image_path': imagePath,
      };

  factory Product.fromMap(Map<String, dynamic> m) => Product(
        id: m['id'],
        name: m['name'],
        category: m['category'] ?? 'General',
        costPrice: Money.fromMinor((m['cost_price'] as num?)?.toInt() ?? 0),
        sellPrice: Money.fromMinor((m['sell_price'] as num?)?.toInt() ?? 0),
        stockQty: (m['stock_qty'] as num).toDouble(),
        reorderLevel: m['reorder_level'],
        bottleMl: (m['bottle_ml'] as num?)?.toInt() ?? 750,
        // Both are read here as well as written in `toMap`. A field written but
        // not read back round-trips as its default, which is how a keg imported
        // as 50 litres came back out of the database as "each, 750 ml" with no
        // error anywhere.
        unit: ProductUnit.parse(m['unit'] as String?),
        trackVariants: ((m['track_variants'] as num?)?.toInt() ?? 0) == 1,
        // 0 for a row written before tanks existed, and for every product that
        // is not stocked by weight — see the field's doc.
        millilitresPerKilogram:
            (m['ml_per_kg'] as num?)?.toDouble() ?? 0,
        halfPrice: (m['half_price'] as num?) == null
            ? null
            : Money.fromMinor((m['half_price'] as num).toInt()),
        quarterPrice: (m['quarter_price'] as num?) == null
            ? null
            : Money.fromMinor((m['quarter_price'] as num).toInt()),
        exciseStampBatch: m['excise_stamp_batch'] ?? '',
        active: m['active'] == 1,
        updatedAt: m['updated_at'] ?? '',
        remoteId: m['remote_id'],
        // An empty string is stored as null: the column is nullable and a blank
        // path is not a path. `fromMap` turning '' into '' would have every
        // reader distinguishing "" from null for no reason.
        imagePath: (m['image_path'] as String?)?.isEmpty ?? true
            ? null
            : m['image_path'] as String,
      );

  /// Row order used for both Excel export and Google Sheets export, so the
  /// two stay identical and a file exported from one can be read by the other.
  ///
  /// Thirteen columns. The twelfth is `barcode` — the product's *primary* code,
  /// which is what nearly every shop needs day to day. A product can hold
  /// several codes, but it cannot hold them in one column, so any additional
  /// codes live on the separate `Barcodes` sheet (see [ProductBarcode]).
  ///
  /// The thirteenth is `unit`, appended rather than inserted so that every
  /// twelve-column workbook already in the field still reads by position. It
  /// exists because `bottle_ml` alone cannot say whether a row's "750" means
  /// 750 millilitres in a bottle or 750 litres in a tank.
  static const sheetHeaders = [
    'id',
    'name',
    'category',
    'cost_price',
    'sell_price',
    'stock_qty',
    'reorder_level',
    'excise_stamp_batch',
    'bottle_ml',
    'half_price',
    'quarter_price',
    'barcode',
    'unit'
  ];

  /// How many columns [sheetHeaders] has. Exported so the Sheets importer's
  /// range constant cannot drift from the header list — the previous design
  /// hardcoded `Inventory!A1:K` next to an eleven-column header, and a twelfth
  /// column added later would have been silently dropped by Google Sheets.
  static const sheetColumnCount = 13;

  /// A1 range covering the whole Inventory sheet, header row included.
  static const sheetRange = 'Inventory!A1:M';

  /// Emitted in whole shillings, not cents: this row is read and edited by
  /// people in a spreadsheet, and a column of 4050 where a human expects 40.50
  /// would be silently misread as a price. The internal representation stays
  /// integer cents; the conversion happens only at this edge.
  List<dynamic> toSheetRow({String? barcode}) => [
        id,
        name,
        category,
        costPrice.asMajor,
        sellPrice.asMajor,
        stockQty,
        reorderLevel,
        exciseStampBatch,
        // Emitted *in the row's declared unit*, which is what the importer
        // reads it back as. Writing millilitres into a row that declares
        // `litre` means a 50-litre keg exported as 50000 and re-imported as
        // 50 000 litres — a thousand-fold error that survives the round trip
        // looking perfectly valid. The column name is historical; its unit is
        // the `unit` column beside it.
        unit == ProductUnit.litre
            ? (bottleMl / millilitresPerLitre)
                .toStringAsFixed(bottleMl % millilitresPerLitre == 0 ? 0 : 3)
            : bottleMl,
        halfPrice?.asMajor ?? '',
        quarterPrice?.asMajor ?? '',
        barcode ?? '',
        unit.wire,
      ];

  /// Shared product-row rules.
  ///
  /// This is the single source of truth for "is this a valid product row". The
  /// editor, the Excel importer and the Google Sheets importer all go through
  /// it, so the editor can never persist a row that the app's own backup format
  /// would later reject (NaN costs poisoning profit, over-long names, negative
  /// portion prices, fractional reorder levels).
  static const maxNameLength = 120;
  static const maxCategoryLength = 80;

  /// Millilitres in one litre. Named rather than inlined because the same
  /// wrong constant — 100, from cents-per-shilling — is the natural mistake
  /// when converting volumes in a codebase that is otherwise all about money.
  static const int millilitresPerLitre = 1000;

  /// Largest serving size, in millilitres.
  ///
  /// Was 10 000, which was the largest *bottle* anyone sells — and it silently
  /// rejected every keg, tank and drum the moment volumes arrived. A 50-litre
  /// keg is 50 000 ml, so a Kenyan shop that buys beer in tanks could not import
  /// its own stock list at all. 200 000 ml admits a 200-litre drum and still
  /// refuses the kind of number that means a mis-parsed cell.
  static const maxBottleMl = 200000;

  /// Smallest serving size. A millilitre is not a selling unit, but a zero is a
  /// missing value, and the two must not be conflated.
  static const minBottleMl = 1;

  /// Validates an already-parsed product. Returns null when valid, otherwise
  /// which rule was broken.
  ///
  /// A CODE, not a sentence. The model layer cannot reach `AppLocalizations`,
  /// and the callers are three: the importer, which writes the reason into a
  /// stored row the shop reads later ([describe] is its English, and the row is
  /// data), and two screens that show it to a human right now — those two map it
  /// through l10n. Returning a sentence here made every screen show it verbatim.
  static ProductProblem? validate({
    required String name,
    required String category,
    required num costPrice,
    required num sellPrice,
    required num stockQty,
    required int reorderLevel,
    required int bottleMl,
    num? halfPrice,
    num? quarterPrice,
  }) {
    if (name.trim().isEmpty) return ProductProblem.name;
    if (name.trim().length > maxNameLength) {
      return ProductProblem.nameTooLong;
    }
    if (category.trim().length > maxCategoryLength) {
      return ProductProblem.categoryTooLong;
    }
    if (!Money.isValidMajor(costPrice)) {
      return ProductProblem.costPrice;
    }
    if (!Money.isValidMajor(sellPrice)) {
      return ProductProblem.sellPrice;
    }
    if (stockQty.isNaN ||
        stockQty.isInfinite ||
        stockQty < 0) {
      return ProductProblem.stockQty;
    }
    if (reorderLevel < 0) return ProductProblem.reorderLevel;
    if (bottleMl > 0 && (bottleMl < minBottleMl || bottleMl > maxBottleMl)) {
      return ProductProblem.size;
    }
    if (halfPrice != null && !Money.isValidMajor(halfPrice)) {
      return ProductProblem.halfPrice;
    }
    if (quarterPrice != null && !Money.isValidMajor(quarterPrice)) {
      return ProductProblem.quarterPrice;
    }
    return null;
  }

  /// Parses one exported/sheet row, returning null when the row is blank,
  /// malformed or missing a required value.
  ///
  /// Never throws. It delegates to [ImportRowParser], the shared parser both
  /// importers use, and returns only its product. A caller that wants to know
  /// *why* a row failed — which is every importer, because a dropped row has to
  /// reach the owner's needs-attention list — calls
  /// [ImportRowParser.parseProductRow] directly and reads [ParsedRow.problem].
  ///
  /// The previous version threw a [FormatException] on the first invalid row,
  /// which aborted the entire workbook: one bad cell in row 2 cost the owner
  /// all 40 products in the file.
  static Product? fromRow(
    List<dynamic> row, {
    int? Function(dynamic)? parseId,
    SheetColumns? columns,
  }) =>
      ImportRowParser.parseProductRow(row, parseId: parseId, columns: columns)
          .product;
}

class SaleItem {
  final int? id;
  final int saleId;
  final int productId;
  final String productName;
  final double qty;

  /// Price per whole unit, in integer cents. [qty] stays a double because it is
  /// a quantity of bottles, not an amount of money; the two are multiplied
  /// once, by [lineTotal], which rounds the result to a whole cent.
  final Money unitPrice;
  final Money unitCost;
  final String portion;
  final int portionMl;

  SaleItem({
    this.id,
    required this.saleId,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.unitPrice,
    required this.unitCost,
    this.portion = 'full',
    this.portionMl = 0,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'sale_id': saleId,
        'product_id': productId,
        'product_name': productName,
        'qty': qty,
        'unit_price': unitPrice.minorUnits,
        'unit_cost': unitCost.minorUnits,
        'portion': portion,
        'portion_ml': portionMl,
      };

  /// The line's amount: unit price scaled by quantity, quantised to whole
  /// cents. A recorded sale total is the exact sum of these.
  Money get total => unitPrice.times(qty);

  factory SaleItem.fromMap(Map<String, dynamic> m) => SaleItem(
        id: m['id'],
        saleId: m['sale_id'],
        productId: m['product_id'],
        productName: m['product_name'],
        qty: (m['qty'] as num).toDouble(),
        unitPrice: Money.fromMinor((m['unit_price'] as num?)?.toInt() ?? 0),
        unitCost: Money.fromMinor((m['unit_cost'] as num?)?.toInt() ?? 0),
        portion: m['portion'] ?? 'full',
        portionMl: (m['portion_ml'] as num?)?.toInt() ?? 0,
      );
}

class Sale {
  final int? id;
  final String staffName;

  /// Integer cents throughout. [total] is stored as the exact sum of the line
  /// amounts, so the ledger reconciles against the items by construction rather
  /// than by luck.
  final Money total;
  final Money profit;
  final String createdAt;
  final String paymentMethod;
  final String? paymentReference;
  final Money amountTendered;
  final Money changeGiven;
  final List<SaleItem> items;

  Sale({
    this.id,
    required this.staffName,
    required this.total,
    required this.profit,
    required this.createdAt,
    this.paymentMethod = 'cash',
    this.paymentReference,
    this.amountTendered = Money.zero,
    this.changeGiven = Money.zero,
    this.items = const [],
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'staff_name': staffName,
        'total': total.minorUnits,
        'profit': profit.minorUnits,
        'payment_method': paymentMethod,
        'payment_reference': paymentReference,
        'amount_tendered': amountTendered.minorUnits,
        'change_given': changeGiven.minorUnits,
        'created_at': createdAt,
      };

  factory Sale.fromMap(Map<String, dynamic> m) {
    final total = Money.fromMinor((m['total'] as num?)?.toInt() ?? 0);
    // Pre-v11 rows recorded a REAL amount_tendered. A zero means "not recorded",
    // not "customer paid nothing", and those rows fall back to the sale total.
    final tendered = (m['amount_tendered'] as num?)?.toInt() ?? 0;
    return Sale(
      id: m['id'],
      staffName: m['staff_name'],
      total: total,
      profit: Money.fromMinor((m['profit'] as num?)?.toInt() ?? 0),
      createdAt: m['created_at'],
      paymentMethod: m['payment_method'] ?? 'cash',
      paymentReference: m['payment_reference'],
      amountTendered: tendered == 0 ? total : Money.fromMinor(tendered),
      changeGiven: Money.fromMinor((m['change_given'] as num?)?.toInt() ?? 0),
    );
  }

  static const sheetHeaders = [
    'id',
    'date',
    'staff',
    'payment_method',
    'amount_tendered',
    'change_given',
    'product',
    'qty',
    'unit_price',
    'line_total'
  ];
  List<List<dynamic>> toSheetRows() => items
      .map((it) => [
            id,
            createdAt,
            staffName,
            paymentMethod,
            amountTendered.asMajor,
            changeGiven.asMajor,
            it.productName,
            it.qty,
            it.unitPrice.asMajor,
            it.unitPrice.times(it.qty).asMajor
          ])
      .toList();
}

/// One barcode a product answers to.
///
/// A product carries *several* of these: the supplier's EAN, a second
/// distributor's, one the owner assigns, and eventually a barcoded excise
/// serial. They live in their own table rather than a column on `products`
/// because `barcode` is the table's primary key, which is the only thing that
/// makes `getProductByBarcode` deterministic by construction: a code can only
/// ever belong to one product, so "which product does this scan mean?" has no
/// ambiguous answer to resolve and therefore no duplicate policy to invent.
class ProductBarcode {
  final String barcode;
  final int productId;

  /// Informational only — every kind scans identically. It exists so a
  /// duplicate found during an import can be *explained* ("this is the
  /// distributor's code for Coke") instead of just rejected.
  final String kind;

  const ProductBarcode({
    required this.barcode,
    required this.productId,
    this.kind = BarcodeKind.supplier,
  });

  Map<String, dynamic> toMap() => {
        'barcode': barcode,
        'product_id': productId,
        'kind': kind,
      };

  factory ProductBarcode.fromMap(Map<String, dynamic> m) => ProductBarcode(
        barcode: m['barcode'] as String,
        productId: m['product_id'] as int,
        kind: (m['kind'] as String?) ?? BarcodeKind.supplier,
      );

  /// Row order for the optional `Barcodes` sheet. Kept beside [Product] so the
  /// export and import shapes cannot drift.
  static const List<String> sheetHeaders = ['product_id', 'barcode', 'kind'];
}

/// One sellable version of a product.
///
/// Variants exist because "Kenyana Beer" is not one thing to a shop: it is dark
/// and regular, and it is sold as a big cup and a small cup, and those four
/// combinations have four different prices and four different stock counts.
/// Modelling that as four products means the shared cost, category and supplier
/// are copied four times and drift apart; modelling it as one product means
/// they cannot be told apart at the till.
///
/// A variant owns its own price, stock and barcode. Those three are the whole
/// reason it exists: everything else (category, cost basis, excise batch) is
/// inherited from the parent.
class ProductVariant {
  final int? id;
  final int productId;

  /// What the seller calls it. "Dark", "Regular", "Big cup", "Small cup".
  final String name;

  /// Optional stock-keeping code. Unique within the product when present.
  final String sku;

  final ProductUnit unit;

  /// Serving size in millilitres. 0 for a countable variant.
  final int sizeMl;

  final Money sellPrice;
  final Money costPrice;
  final double stockQty;
  final int reorderLevel;

  /// Display order. Explicit because "Dark before Regular" is a shop
  /// preference, not alphabetical accident.
  final int position;
  final bool active;

  const ProductVariant({
    this.id,
    required this.productId,
    required this.name,
    this.sku = '',
    this.unit = ProductUnit.each,
    this.sizeMl = 0,
    required this.sellPrice,
    this.costPrice = Money.zero,
    this.stockQty = 0,
    this.reorderLevel = 0,
    this.position = 0,
    this.active = true,
  });

  bool get isLow => stockQty <= reorderLevel;

  /// How much this is worth at cost, for the dashboard's stock valuation.
  Money get stockValue => costPrice.times(stockQty);

  /// The label the till shows: "Dark 500 ml", or just "Dark".
  String get label {
    if (sizeMl <= 0) return name;
    final unitText = Volume(sizeMl.toDouble()).display;
    return '$name $unitText';
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'product_id': productId,
        'name': name,
        'sku': sku,
        'unit': unit.wire,
        'size_ml': sizeMl,
        'sell_price': sellPrice.minorUnits,
        'cost_price': costPrice.minorUnits,
        'stock_qty': stockQty,
        'reorder_level': reorderLevel,
        'position': position,
        'active': active ? 1 : 0,
      };

  factory ProductVariant.fromMap(Map<String, dynamic> m) => ProductVariant(
        id: m['id'] as int?,
        productId: m['product_id'] as int,
        name: (m['name'] as String? ?? '').trim(),
        sku: (m['sku'] as String? ?? '').trim(),
        unit: ProductUnit.parse(m['unit'] as String?),
        sizeMl: (m['size_ml'] as num?)?.round() ?? 0,
        sellPrice: Money.fromMinor((m['sell_price'] as num?)?.round() ?? 0),
        costPrice: Money.fromMinor((m['cost_cost'] as num?)?.round() ??
            (m['cost_price'] as num?)?.round() ??
            0),
        stockQty: ((m['stock_qty'] as num?) ?? 0).toDouble(),
        reorderLevel: (m['reorder_level'] as num?)?.round() ?? 0,
        position: (m['position'] as num?)?.round() ?? 0,
        active: ((m['active'] as num?)?.toInt() ?? 1) == 1,
      );

  /// Row order for the optional `Variants` sheet. Beside the model so the
  /// export and import shapes cannot drift apart, exactly as
  /// [ProductBarcode.sheetHeaders] is.
  static const List<String> sheetHeaders = [
    'product_id',
    'variant_id',
    'name',
    'sku',
    'unit',
    'size_ml',
    'sell_price',
    'cost_price',
    'stock_qty',
    'reorder_level',
  ];

  static const int sheetColumnCount = 10;
}

/// A row from an import that could not be written, kept for the owner to fix.
///
/// The alternative — dropping it, which is what every importer did — loses the
/// row with no trace. Keeping the original values means the fix is a
/// re-import of an edited row rather than a hunt for the supplier's workbook.
class ImportNeedsAttention {
  final int? id;

  /// 'excel' | 'sheets' | 'backup'
  final String source;
  final String sheetName;

  /// 1-based, as a spreadsheet shows it, so "row 4" means what the owner sees.
  final int rowNumber;

  final String rawName;

  /// The original row, as JSON. Never interpreted again — kept so the owner can
  /// see what was actually in their file.
  final String rawRow;

  /// The header-to-field mapping the import parsed the row with, as JSON —
  /// `SheetColumns.toJson`. Null means "the canonical column order", which is
  /// what a header-less file (or a row recorded before the mapping was kept)
  /// used. Without it the raw row's cells cannot be read back in the fields
  /// they were read from.
  final String? columnMap;

  /// One sentence, in the owner's language: what is wrong and what to do.
  final String problem;

  final bool resolved;
  final DateTime createdAt;

  const ImportNeedsAttention({
    this.id,
    required this.source,
    this.sheetName = '',
    required this.rowNumber,
    this.rawName = '',
    required this.rawRow,
    required this.problem,
    this.resolved = false,
    required this.createdAt,
    this.columnMap,
  });

  /// "Row 14 — Kwancheri Lager", for a list title.
  String get label {
    final name = rawName.trim().isEmpty ? '(no name)' : rawName.trim();
    final where = rowNumber > 0 ? 'Row $rowNumber · $name' : name;
    return where;
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'source': source,
        'sheet_name': sheetName,
        'row_number': rowNumber,
        'raw_name': rawName,
        'raw_row': rawRow,
        'problem': problem,
        'resolved': resolved ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'column_map': columnMap,
      };

  factory ImportNeedsAttention.fromMap(Map<String, dynamic> m) =>
      ImportNeedsAttention(
        id: m['id'] as int?,
        source: (m['source'] as String?) ?? 'excel',
        sheetName: (m['sheet_name'] as String?) ?? '',
        rowNumber: (m['row_number'] as num?)?.round() ?? 0,
        rawName: (m['raw_name'] as String?) ?? '',
        rawRow: (m['raw_row'] as String?) ?? '[]',
        problem: (m['problem'] as String?) ?? 'Could not be imported',
        resolved: ((m['resolved'] as num?)?.toInt() ?? 0) == 1,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        columnMap: (m['column_map'] as String?)?.isEmpty ?? true
            ? null
            : m['column_map'] as String,
      );
}

/// Category normalisation.
///
/// A real vocabulary rather than a free-text column, because three importers
/// and the editor each defaulted to the literal string `'General'` and nothing
/// reconciled spelling. A supplier file containing `Drinks`, `drinks` and
/// `drinks ` produced three categories and three separate reports, which is
/// worse than having no categories at all.
class CategoryName {
  const CategoryName._();

  /// The fallback when a row genuinely has no category.
  static const general = 'General';

  /// Names a shop would recognise. Purely a seed list: the table is the source
  /// of truth once populated, and an unknown name from an import is added to it
  /// rather than being forced into one of these.
  static const seeds = <String>[
    general,
    'Beer',
    'Wines & Spirits',
    'Soft Drinks',
    'Water',
    'Juice',
    'Milk & Dairy',
    'Groceries',
    'Bakery',
    'Produce',
    'Meat & Fish',
    'Household',
    'Personal Care',
    'Snacks',
    'Cigarettes & Tobacco',
    'Stationery',
    'Other',
  ];

  /// Canonical form of a category from any source.
  ///
  /// Collapses whitespace and title-cases, so `  soft   drinks `, `Soft Drinks`
  /// and `SOFT DRINKS` are one category. Acronyms are restored afterwards,
  /// because title-casing would turn `eTIMS` into `Etims` and `PVC` into `Pvc`.
  static String normalise(String? raw) {
    final collapsed = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return general;

    // "and" becomes "&" before anything else, so "wines and spirits" and the
    // seeded "Wines & Spirits" are the same category. Without this a supplier's
    // spreadsheet writes them as two, and the owner gets two half-empty
    // categories and two reports that each look complete.
    final ampersanded = collapsed.replaceAll(
      RegExp(r'\s+and\s+', caseSensitive: false),
      ' & ',
    );

    final words = ampersanded
        .toLowerCase()
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) {
      if (_acronyms.contains(word.toUpperCase())) return word.toUpperCase();
      if (word.length <= 2) return word.toUpperCase();
      return word[0].toUpperCase() + word.substring(1);
    });
    final joined = words.join(' ');
    return joined.isEmpty ? general : joined;
  }

  static const _acronyms = {'etims', 'mpesa', 'pvc', 'tvs', 'usb', 'sms'};
}

/// The recognised barcode kinds. A const class rather than an `enum` because
/// the value is written straight to a TEXT column with no default and read back
/// into a plain string, and an enum would invite a `.name` round-trip that the
/// schema does not enforce.
class BarcodeKind {
  const BarcodeKind._();

  /// The code a supplier printed on the product.
  static const String supplier = 'supplier';

  /// A code the shop owner assigned themselves.
  static const String own = 'own';

  /// A barcoded excise serial, tracked per stamp.
  static const String excise = 'excise';

  static const List<String> kinds = [supplier, own, excise];

  /// Normalises free text from an import into a known kind.
  ///
  /// An unknown value becomes [supplier] rather than being rejected: the kind
  /// is a label for explaining a duplicate, and refusing a whole import row
  /// because a supplier's spreadsheet spelled it differently is a worse
  /// outcome than an imprecise label.
  static String parse(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    return kinds.contains(value) ? value : supplier;
  }

  /// Human-readable label for the editor.
  static String label(String kind) => switch (kind) {
        own => 'Shop-assigned',
        excise => 'Excise serial',
        _ => 'Supplier',
      };
}

/// A cashier's shift session.
///
/// A shift is the period a till is open under one person. It is the unit of
/// account for reconciliation: a cashier opens a shift with a known float,
/// rings up sales, and closes it by counting the till and recording the
/// difference. Multishop tills scope shifts by workspace key, so each shop's
/// shifts live in their own database file.
class Shift {
  final int? id;
  final int staffId;
  final String staffName;
  final String startTime;
  final String? endTime;
  final Money startFloat;
  final Money endFloat;

  /// 'open' while the shift is live, 'closed' once reconciled.
  final String status;

  Shift({
    this.id,
    required this.staffId,
    required this.staffName,
    required this.startTime,
    this.endTime,
    required this.startFloat,
    this.endFloat = Money.zero,
    this.status = 'open',
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'staff_id': staffId,
        'staff_name': staffName,
        'start_time': startTime,
        'end_time': endTime,
        'start_float': startFloat.minorUnits,
        'end_float': endFloat.minorUnits,
        'status': status,
      };

  factory Shift.fromMap(Map<String, dynamic> m) => Shift(
        id: m['id'] as int?,
        staffId: (m['staff_id'] as num?)?.toInt() ?? 0,
        staffName: (m['staff_name'] as String?) ?? '',
        startTime: (m['start_time'] as String?) ?? '',
        endTime: m['end_time'] as String?,
        startFloat: Money.fromMinor((m['start_float'] as num?)?.toInt() ?? 0),
        endFloat: Money.fromMinor((m['end_float'] as num?)?.toInt() ?? 0),
        status: (m['status'] as String?) ?? 'open',
      );
}

/// One denomination counted during a till reconciliation.
///
/// A cashier counts physical cash into named piles — "five 100-shilling coins"
/// — and the reconciliation totals those piles. Recording each pile keeps an
/// auditable trail of *how* the till was counted, not just the sum.
class TillCount {
  final int? id;
  final int shiftId;

  /// A display label, e.g. "KSh 100", "KSh 50", "KSh 20".
  final String denomination;
  final int count;
  final Money value;
  final String createdAt;

  TillCount({
    this.id,
    required this.shiftId,
    required this.denomination,
    required this.count,
    required this.value,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'shift_id': shiftId,
        'denomination': denomination,
        'count': count,
        'value': value.minorUnits,
        'created_at': createdAt,
      };

  factory TillCount.fromMap(Map<String, dynamic> m) => TillCount(
        id: m['id'] as int?,
        shiftId: (m['shift_id'] as num?)?.toInt() ?? 0,
        denomination: (m['denomination'] as String?) ?? '',
        count: (m['count'] as num?)?.toInt() ?? 0,
        value: Money.fromMinor((m['value'] as num?)?.toInt() ?? 0),
        createdAt: (m['created_at'] as String?) ?? '',
      );
}

/// The result of closing a shift.
///
/// Stored separately from [Shift] because a shift can be closed and re-counted
/// — the reconciliation is a discrete event that happens at the end of the
/// shift, and an owner may want to see every reconciliation attempt.
class Reconciliation {
  final int? id;
  final int shiftId;
  final Money countedCash;
  final Money expectedCash;
  final Money variance;
  final String recordedAt;

  Reconciliation({
    this.id,
    required this.shiftId,
    required this.countedCash,
    required this.expectedCash,
    required this.variance,
    required this.recordedAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'shift_id': shiftId,
        'counted_cash': countedCash.minorUnits,
        'expected_cash': expectedCash.minorUnits,
        'variance': variance.minorUnits,
        'recorded_at': recordedAt,
      };

  factory Reconciliation.fromMap(Map<String, dynamic> m) => Reconciliation(
        id: m['id'] as int?,
        shiftId: (m['shift_id'] as num?)?.toInt() ?? 0,
        countedCash: Money.fromMinor((m['counted_cash'] as num?)?.toInt() ?? 0),
        expectedCash:
            Money.fromMinor((m['expected_cash'] as num?)?.toInt() ?? 0),
        variance: Money.fromMinor((m['variance'] as num?)?.toInt() ?? 0),
        recordedAt: (m['recorded_at'] as String?) ?? '',
      );
}

/// A fixed shot cup configuration.
///
/// Shots are sold in a standard cup size at a fixed price, but the underlying
/// inventory product can be any drink — a spirit, a liqueur, a fortified wine.
/// The linkage is by [productId] so the cup configuration can move with the
/// product if it is renamed, and the cup keeps its own price so changing the
/// product's sell price does not reprice every shot.
class ShotCup {
  final int? id;
  final int productId;
  final String productName;

  /// The capacity of one shot cup, in millilitres.
  final int capacityMl;

  /// The price of one shot, in minor units.
  final Money price;

  /// Display name for the cup, e.g. "Shot".
  final String label;
  final bool active;
  final String updatedAt;

  ShotCup({
    this.id,
    required this.productId,
    required this.productName,
    required this.capacityMl,
    required this.price,
    this.label = 'Shot',
    this.active = true,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'product_id': productId,
        'product_name': productName,
        'capacity_ml': capacityMl,
        'price': price.minorUnits,
        'label': label,
        'active': active ? 1 : 0,
        'updated_at': updatedAt,
      };

  factory ShotCup.fromMap(Map<String, dynamic> m) => ShotCup(
        id: m['id'] as int?,
        productId: (m['product_id'] as num?)?.toInt() ?? 0,
        productName: (m['product_name'] as String?) ?? '',
        capacityMl: (m['capacity_ml'] as num?)?.toInt() ?? 30,
        price: Money.fromMinor((m['price'] as num?)?.toInt() ?? 0),
        label: (m['label'] as String?) ?? 'Shot',
        active: m['active'] == 1,
        updatedAt: (m['updated_at'] as String?) ?? '',
      );
}

/// A user-entered cup size suggestion for beer/keg products.
///
/// When a shop sells by the cup from a keg or tank, the cup sizes used are shop
/// specific. This stores the sizes the user has entered so they appear as
/// suggestions when adding a new cup size, rather than the shop re-typing "330",
/// "500", "660" on every product.
class CupSizeSuggestion {
  final int? id;
  final int? productId;
  final int sizeMl;
  final int useCount;
  final String createdAt;

  CupSizeSuggestion({
    this.id,
    this.productId,
    required this.sizeMl,
    this.useCount = 1,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'product_id': productId,
        'size_ml': sizeMl,
        'use_count': useCount,
        'created_at': createdAt,
      };

  factory CupSizeSuggestion.fromMap(Map<String, dynamic> m) =>
      CupSizeSuggestion(
        id: m['id'] as int?,
        productId: m['product_id'] as int?,
        sizeMl: (m['size_ml'] as num?)?.toInt() ?? 0,
        useCount: (m['use_count'] as num?)?.toInt() ?? 0,
        createdAt: (m['created_at'] as String?) ?? '',
      );
}

class StockAdjustment {
  final int? id;
  final int productId;
  final String productName;
  final int delta;
  final String reason;
  final String staffName;
  final String createdAt;

  StockAdjustment({
    this.id,
    required this.productId,
    required this.productName,
    required this.delta,
    required this.reason,
    required this.staffName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'product_id': productId,
        'product_name': productName,
        'delta': delta,
        'reason': reason,
        'staff_name': staffName,
        'created_at': createdAt,
      };

  factory StockAdjustment.fromMap(Map<String, dynamic> m) => StockAdjustment(
        id: m['id'],
        productId: m['product_id'],
        productName: m['product_name'],
        delta: m['delta'],
        reason: m['reason'] ?? '',
        staffName: m['staff_name'],
        createdAt: m['created_at'],
      );
}
