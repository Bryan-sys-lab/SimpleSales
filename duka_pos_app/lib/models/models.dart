/// Core data models. Kept as plain classes with toMap/fromMap so they map
/// directly onto SQLite rows (see db/database_helper.dart) and onto
/// spreadsheet rows (see services/sheets_service.dart, services/excel_service.dart) —
/// one shape used everywhere avoids three slightly different versions drifting apart.
library;

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
  final double costPrice;
  final double sellPrice;
  final double stockQty;
  final int reorderLevel;
  final int bottleMl;
  final double? halfPrice;
  final double? quarterPrice;
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

  double get marginPct =>
      sellPrice == 0 ? 0 : ((sellPrice - costPrice) / sellPrice) * 100;
  bool get isLow => stockQty <= reorderLevel;
  double priceFor(String portion) => portion == 'half'
      ? (halfPrice ?? sellPrice / 2)
      : portion == 'quarter'
          ? (quarterPrice ?? sellPrice / 4)
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
    double? costPrice,
    double? sellPrice,
    double? stockQty,
    int? reorderLevel,
    int? bottleMl,
    double? halfPrice,
    double? quarterPrice,
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
        'cost_price': costPrice,
        'sell_price': sellPrice,
        'stock_qty': stockQty,
        'reorder_level': reorderLevel,
        'bottle_ml': bottleMl,
        'half_price': halfPrice,
        'quarter_price': quarterPrice,
        'excise_stamp_batch': exciseStampBatch,
        'active': active ? 1 : 0,
        'updated_at': updatedAt,
        'remote_id': remoteId,
      };

  factory Product.fromMap(Map<String, dynamic> m) => Product(
        id: m['id'],
        name: m['name'],
        category: m['category'] ?? 'General',
        costPrice: (m['cost_price'] as num).toDouble(),
        sellPrice: (m['sell_price'] as num).toDouble(),
        stockQty: (m['stock_qty'] as num).toDouble(),
        reorderLevel: m['reorder_level'],
        bottleMl: (m['bottle_ml'] as num?)?.toInt() ?? 750,
        halfPrice: (m['half_price'] as num?)?.toDouble(),
        quarterPrice: (m['quarter_price'] as num?)?.toDouble(),
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
  List<dynamic> toSheetRow() => [
        id,
        name,
        category,
        costPrice,
        sellPrice,
        stockQty,
        reorderLevel,
        exciseStampBatch,
        bottleMl,
        halfPrice ?? '',
        quarterPrice ?? ''
      ];
}

class SaleItem {
  final int? id;
  final int saleId;
  final int productId;
  final String productName;
  final double qty;
  final double unitPrice;
  final double unitCost;
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
        'unit_price': unitPrice,
        'unit_cost': unitCost,
        'portion': portion,
        'portion_ml': portionMl,
      };

  factory SaleItem.fromMap(Map<String, dynamic> m) => SaleItem(
        id: m['id'],
        saleId: m['sale_id'],
        productId: m['product_id'],
        productName: m['product_name'],
        qty: (m['qty'] as num).toDouble(),
        unitPrice: (m['unit_price'] as num).toDouble(),
        unitCost: (m['unit_cost'] as num).toDouble(),
        portion: m['portion'] ?? 'full',
        portionMl: (m['portion_ml'] as num?)?.toInt() ?? 0,
      );
}

class Sale {
  final int? id;
  final String staffName;
  final double total;
  final double profit;
  final String createdAt;
  final String paymentMethod;
  final String? paymentReference;
  final double amountTendered;
  final double changeGiven;
  final List<SaleItem> items;

  Sale({
    this.id,
    required this.staffName,
    required this.total,
    required this.profit,
    required this.createdAt,
    this.paymentMethod = 'cash',
    this.paymentReference,
    this.amountTendered = 0,
    this.changeGiven = 0,
    this.items = const [],
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'staff_name': staffName,
        'total': total,
        'profit': profit,
        'payment_method': paymentMethod,
        'payment_reference': paymentReference,
        'amount_tendered': amountTendered,
        'change_given': changeGiven,
        'created_at': createdAt,
      };

  factory Sale.fromMap(Map<String, dynamic> m) => Sale(
        id: m['id'],
        staffName: m['staff_name'],
        total: (m['total'] as num).toDouble(),
        profit: (m['profit'] as num).toDouble(),
        createdAt: m['created_at'],
        paymentMethod: m['payment_method'] ?? 'cash',
        paymentReference: m['payment_reference'],
        amountTendered: ((m['amount_tendered'] as num?)?.toDouble() ?? 0) == 0
            ? (m['total'] as num).toDouble()
            : (m['amount_tendered'] as num).toDouble(),
        changeGiven: (m['change_given'] as num?)?.toDouble() ?? 0,
      );

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
            amountTendered,
            changeGiven,
            it.productName,
            it.qty,
            it.unitPrice,
            it.qty * it.unitPrice
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
