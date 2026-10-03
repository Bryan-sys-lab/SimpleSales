/// Core data models. Kept as plain classes with toMap/fromMap so they map
/// directly onto SQLite rows (see db/database_helper.dart) and onto
/// spreadsheet rows (see services/sheets_service.dart, services/excel_service.dart) —
/// one shape used everywhere avoids three slightly different versions drifting apart.
library;

import '../utils/money.dart';

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
  final String pinHash;
  final bool active;
  final String? remoteId;
  final String role;

  Staff(
      {this.id,
      required this.name,
      required this.pinHash,
      this.active = true,
      this.remoteId,
      this.role = 'cashier'});

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'pin_hash': pinHash,
        'active': active ? 1 : 0,
        'remote_id': remoteId,
        'role': role,
      };

  factory Staff.fromMap(Map<String, dynamic> m) => Staff(
        id: m['id'],
        name: m['name'],
        pinHash: m['pin_hash'],
        active: m['active'] == 1,
        remoteId: m['remote_id'],
        role: m['role'] ?? 'cashier',
      );
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
  final Money? halfPrice;
  final Money? quarterPrice;
  final String exciseStampBatch;
  final bool active;
  final String updatedAt;
  final String?
      remoteId; // Supabase products.id, once synced — see backend_service.dart

  Product({
    this.id,
    required this.name,
    required this.category,
    required this.costPrice,
    required this.sellPrice,
    required this.stockQty,
    required this.reorderLevel,
    this.bottleMl = 750,
    this.halfPrice,
    this.quarterPrice,
    this.exciseStampBatch = '',
    this.active = true,
    required this.updatedAt,
    this.remoteId,
  });

  /// Computed from minor units so the ratio does not inherit float error from
  /// the two prices. Percentages are for display, so the final division to a
  /// double is expected and harmless.
  double get marginPct => sellPrice.isZero
      ? 0
      : ((sellPrice.minorUnits - costPrice.minorUnits) /
              sellPrice.minorUnits) *
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
        'half_price': halfPrice?.minorUnits,
        'quarter_price': quarterPrice?.minorUnits,
        'excise_stamp_batch': exciseStampBatch,
        'active': active ? 1 : 0,
        'updated_at': updatedAt,
        'remote_id': remoteId,
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
      );

  /// Row order used for both Excel export and Google Sheets export, so the
  /// two stay identical and a file exported from one can be read by the other.
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
    'quarter_price'
  ];
  /// Emitted in whole shillings, not cents: this row is read and edited by
  /// people in a spreadsheet, and a column of 4050 where a human expects 40.50
  /// would be silently misread as a price. The internal representation stays
  /// integer cents; the conversion happens only at this edge.
  List<dynamic> toSheetRow() => [
        id,
        name,
        category,
        costPrice.asMajor,
        sellPrice.asMajor,
        stockQty,
        reorderLevel,
        exciseStampBatch,
        bottleMl,
        halfPrice?.asMajor ?? '',
        quarterPrice?.asMajor ?? ''
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
  static const maxBottleMl = 10000;

  /// Validates an already-parsed product. Returns null when valid, otherwise a
  /// human-readable reason suitable for display.
  static String? validate({
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
    if (name.trim().isEmpty) return 'Enter a product name';
    if (name.trim().length > maxNameLength) {
      return 'Product name must be $maxNameLength characters or fewer';
    }
    if (category.trim().length > maxCategoryLength) {
      return 'Category must be $maxCategoryLength characters or fewer';
    }
    if (!Money.isValidMajor(costPrice)) {
      return 'Cost price must be a valid amount of 0 or more';
    }
    if (!Money.isValidMajor(sellPrice)) {
      return 'Selling price must be a valid amount of 0 or more';
    }
    if (!stockQty.isFinite || stockQty < 0) {
      return 'Stock quantity must be 0 or more';
    }
    if (reorderLevel < 0) return 'Reorder level must be 0 or more';
    if (bottleMl < 1 || bottleMl > maxBottleMl) {
      return 'Bottle size must be between 1 and $maxBottleMl ml';
    }
    if (halfPrice != null && !Money.isValidMajor(halfPrice)) {
      return 'Half price must be a valid amount of 0 or more';
    }
    if (quarterPrice != null && !Money.isValidMajor(quarterPrice)) {
      return 'Quarter price must be a valid amount of 0 or more';
    }
    return null;
  }

  /// Parses one exported/sheet row using [validate]. Returns null when the row
  /// is blank or malformed so importers can skip/report consistently.
  static Product? fromRow(
    List<dynamic> row, {
    int? Function(dynamic)? parseId,
  }) {
    if (row.length < 7) return null;
    final rawName = (row.length > 1 ? row[1]?.toString() ?? '' : '').trim();
    if (rawName.isEmpty) return null;

    double? num_(int i) {
      if (i >= row.length) return null;
      final text = row[i]?.toString().trim() ?? '';
      if (text.isEmpty) return null;
      return double.tryParse(text);
    }

    final cost = num_(3);
    final price = num_(4);
    final stock = num_(5);
    final reorder = num_(6)?.round();
    final bottleMl = (num_(8) ?? 750).round();
    final half = num_(9);
    final quarter = num_(10);
    final category =
        ((row.length > 2 ? row[2]?.toString() ?? '' : '').trim()).isEmpty
            ? 'General'
            : row[2].toString().trim();

    final problem = validate(
      name: rawName,
      category: category,
      costPrice: cost ?? double.nan,
      sellPrice: price ?? double.nan,
      stockQty: stock ?? double.nan,
      reorderLevel: reorder ?? -1,
      bottleMl: bottleMl,
      halfPrice: half,
      quarterPrice: quarter,
    );
    if (problem != null) throw FormatException(problem);

    return Product(
      id: row.isNotEmpty && parseId != null ? parseId(row[0]) : null,
      name: rawName,
      category: category,
      costPrice: Money.fromMajor(cost!),
      sellPrice: Money.fromMajor(price!),
      stockQty: stock!.toDouble(),
      reorderLevel: reorder!,
      bottleMl: bottleMl,
      halfPrice: half == null ? null : Money.fromMajor(half),
      quarterPrice: quarter == null ? null : Money.fromMajor(quarter),
      exciseStampBatch: row.length > 7 ? (row[7]?.toString() ?? '') : '',
      updatedAt: DateTime.now().toIso8601String(),
    );
  }
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
