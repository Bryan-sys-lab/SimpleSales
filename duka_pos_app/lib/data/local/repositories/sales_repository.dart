import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';
import '../../../models/layby.dart';
import '../../../models/models.dart';
import '../../../models/stock_movement.dart';
import '../../../profile/shop_profile.dart';
import 'finance_repository.dart';
import '../../../utils/money.dart';

/// Repository for sales and sale items.
///
/// Delegates to [DatabaseHelper] for now; the SQL is owned by [DatabaseHelper]
/// until Phase 8 moves it into this repository. Transaction-aware variants
/// accept an open [Transaction] and never open their own transaction, so a
/// sale, its items, stock movement and financial event can commit atomically.
class SalesRepository {
  SalesRepository._();
  static final SalesRepository instance = SalesRepository._();

  /// Creates (or verifies) the `sales` and `sale_items` tables.
  ///
  /// The DDL mirrors `_onCreate` exactly so fresh installs and upgraded
  /// tills cannot diverge. Called by [schema] `_onCreate`.
  static Future<void> createTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS sales (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      staff_name TEXT NOT NULL,
      staff_id INTEGER,
      total INTEGER NOT NULL,
      profit INTEGER NOT NULL,
      payment_method TEXT NOT NULL DEFAULT 'cash',
      payment_reference TEXT,
      amount_tendered INTEGER NOT NULL DEFAULT 0,
      change_given INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      vat_rate_percent INTEGER,
      etims_status TEXT,
      etims_receipt_number TEXT,
      etims_qr_payload TEXT,
      payment_verified INTEGER NOT NULL DEFAULT 1,
      payment_confirmed_at TEXT,
      subtotal_minor INTEGER,
      order_discount_minor INTEGER NOT NULL DEFAULT 0,
      order_discount_reason_id INTEGER,
      discount_approved_by INTEGER,
      buyer_name TEXT,
      buyer_tin TEXT,
      synced_to_backend INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_date ON sales (created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_staff ON sales (staff_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_payment_verified ON sales (payment_verified, created_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_etims_status ON sales (etims_status)');

    await db.execute('''CREATE TABLE IF NOT EXISTS sale_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      qty REAL NOT NULL,
      unit_price INTEGER NOT NULL,
      unit_cost INTEGER NOT NULL,
      portion TEXT NOT NULL DEFAULT 'full',
      portion_ml INTEGER NOT NULL DEFAULT 0,
      variant_id INTEGER,
      variant_name TEXT NOT NULL DEFAULT '',
      pack_id INTEGER,
      pack_qty REAL,
      list_unit_price_minor INTEGER,
      discount_minor INTEGER NOT NULL DEFAULT 0,
      discount_reason_id INTEGER,
      price_overridden INTEGER NOT NULL DEFAULT 0,
      tax_rule_id TEXT,
      tax_rule_version INTEGER,
      FOREIGN KEY (sale_id) REFERENCES sales (id)
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items (product_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items (sale_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_tax_rule ON sale_items (tax_rule_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS receipt_shares (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      sale_id INTEGER NOT NULL,
      token TEXT,
      url TEXT,
      recipient_masked TEXT,
      created_at TEXT NOT NULL,
      expires_at TEXT,
      revoked_at TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_receipt_shares_sale '
        'ON receipt_shares (sale_id, created_at)');

    await db.execute('''CREATE TABLE IF NOT EXISTS held_carts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      customer_id INTEGER,
      created_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'held'
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS held_cart_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      held_cart_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      qty REAL NOT NULL,
      portion TEXT NOT NULL,
      portion_ml INTEGER NOT NULL DEFAULT 0,
      variant_id INTEGER,
      variant_name TEXT NOT NULL DEFAULT '',
      shot_cup_id INTEGER,
      shot_label TEXT,
      shot_capacity_ml INTEGER,
      shot_price INTEGER,
      unit_price INTEGER NOT NULL,
      unit_cost INTEGER NOT NULL,
      discount_minor INTEGER NOT NULL DEFAULT 0,
      discount_reason_id INTEGER,
      pack_id INTEGER,
      pack_qty REAL,
      FOREIGN KEY (held_cart_id) REFERENCES held_carts (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_held_cart_lines_cart '
        'ON held_cart_lines (held_cart_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS pending_etims (
      sale_id INTEGER PRIMARY KEY,
      receipt_number TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pending_etims_created ON pending_etims (created_at)');

    await db.execute('''CREATE TABLE IF NOT EXISTS import_needs_attention (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source TEXT NOT NULL,
      sheet_name TEXT NOT NULL DEFAULT '',
      row_number INTEGER NOT NULL DEFAULT 0,
      raw_name TEXT NOT NULL DEFAULT '',
      raw_row TEXT NOT NULL,
      problem TEXT NOT NULL,
      resolved INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      column_map TEXT
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_import_attention_open
      ON import_needs_attention (resolved, created_at)''');
  }

  /// Creates (or verifies) the `sale_payments` table.
  ///
  /// Mirrors `_createFoundationTables`. Must run after `sales` exists
  /// (`sale_payments.sale_id` references `sales.id`).
  static Future<void> createSalePaymentsTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS sale_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      sale_id INTEGER NOT NULL,
      method TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      tendered_minor INTEGER,
      change_minor INTEGER,
      reference TEXT,
      status TEXT NOT NULL DEFAULT 'confirmed',
      pending_payment_id INTEGER,
      created_at TEXT NOT NULL,
      FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_payments_sale ON sale_payments (sale_id)');
  }

  // ── Transaction-aware variants ─────────────────────────────────────

  /// Records a sale within [txn], which is already part of a larger
  /// transaction. Never opens its own transaction.
  ///
  /// Settings (till code, VAT rate, tax rule, credit limit) are read through
  /// [DatabaseHelper] executor helpers so reads never happen inside a write
  /// transaction, avoiding sqflite_ffi deadlocks. Pass them in explicitly;
  /// they are read once before the transaction opens.
  Future<int> recordSaleInTransaction(Transaction txn, {
    required String staffName,
    required List<SaleItem> items,
    List<SaleTender>? tenders,
    bool enforceStock = true,
    String paymentMethod = 'cash',
    String? paymentReference,
    Money? amountTendered,
    int? staffId,
    bool etimsPending = false,
    bool paymentVerified = true,
    int? customerId,
    int? creditApprovedBy,
    int? discountApprovedBy,
    int? orderDiscountReasonId,
    int? laybyId,
    String tillCode = '',
    int vatRatePercent = 0,
    String taxRuleId = '',
    int taxRuleVersion = 0,
    int defaultLimitMinor = 0,
  }) async {
    if (items.isEmpty) {
      throw StateError('A sale must contain at least one item');
    }
    const allowedPaymentMethods = {
      'cash',
      'card',
      'bank_transfer',
      'mobile_money_manual',
      'mpesa',
      'mpesa_till',
      'credit',
      'layby',
      'exchange_credit',
      'split'
    };
    if (!allowedPaymentMethods.contains(paymentMethod)) {
      throw StateError('Unsupported payment method');
    }
    if (paymentMethod == 'credit' && customerId == null) {
      throw StateError('A credit sale must name the customer taking it');
    }
    if (paymentMethod == 'layby' && laybyId == null) {
      throw StateError('A lay-by sale must name the lay-by');
    }
    if (paymentMethod != 'layby' && laybyId != null) {
      throw StateError('A lay-by may only be completed as a lay-by sale');
    }
    if (items.any((item) => item.qty <= 0 || !item.qty.isFinite)) {
      throw StateError('Sale quantities must be positive');
    }
    final subtotal = sumMoney(items.map((it) => it.unitPrice.times(it.qty)));
    final total = sumMoney(items.map((it) => it.total));
    if (items.any((it) =>
        it.discount.isNegative || it.discount > it.unitPrice.times(it.qty))) {
      throw StateError('A discount cannot exceed its line total');
    }
    final tenderRows = tenders ??
        <SaleTender>[
          SaleTender(
            method: paymentMethod,
            amount: total,
            tendered: amountTendered ?? total,
            reference: paymentReference,
            status: paymentVerified ? 'confirmed' : 'unverified',
          ),
        ];
    if (tenderRows.isEmpty ||
        tenderRows.any(
            (tender) => tender.amount.isNegative || tender.amount.isZero)) {
      throw StateError('Payment amounts must be positive');
    }
    final tenderTotal = sumMoney(tenderRows.map((tender) => tender.amount));
    if (tenderTotal != total) {
      throw StateError('Payment tenders must add up to the sale total');
    }
    if (tenders != null) {
      for (final tender in tenderRows) {
        if (!allowedPaymentMethods.contains(tender.method)) {
          throw StateError('Unsupported payment method');
        }
      }
      final largest = tenderRows.reduce((a, b) => a.amount >= b.amount ? a : b);
      paymentMethod = tenderRows.length == 1 ? largest.method : 'split';
    }
    final paid = paymentMethod == 'credit' || paymentMethod == 'layby'
        ? total
        : (tenders == null
            ? (amountTendered ?? total)
            : sumMoney(
                tenderRows.map((tender) => tender.tendered ?? tender.amount)));
    if (paid.isNegative) {
      throw StateError('Amount received cannot be less than the sale total');
    }
    if (paid < total) {
      throw StateError('Amount received cannot be less than the sale total');
    }
    final change = paymentMethod == 'credit' || paymentMethod == 'layby'
        ? Money.zero
        : paid - total;
    final now = DateTime.now().toIso8601String();
    final eventAtUtc = DateTime.now().toUtc().toIso8601String();

    Future<int> write(DatabaseExecutor txn) async {
      Map<String, dynamic>? laybyRow;
      List<Map<String, dynamic>> laybyItemRows = const [];
      if (laybyId != null) {
        final rows = await txn.query('laybys',
            where: 'id = ?', whereArgs: [laybyId], limit: 1);
        if (rows.isEmpty || rows.first['status'] != LaybyStatus.open.wire) {
          throw StateError('Lay-by is not open');
        }
        laybyRow = rows.first;
        laybyItemRows = await txn.query('layby_items',
            where: 'layby_id = ?', whereArgs: [laybyId], orderBy: 'id ASC');
        if ((laybyRow['total_minor'] as num).toInt() != total.minorUnits ||
            (laybyRow['paid_minor'] as num).toInt() != total.minorUnits) {
          throw StateError('Lay-by balance does not match the sale');
        }
        customerId = (laybyRow['customer_id'] as num).toInt();
      }
      final frozen = await txn.query(
        'stock_counts',
        where: "status = 'in_progress' AND freeze = 1",
        limit: 1,
      );
      if (frozen.isNotEmpty) {
        final countId = frozen.first['id'] as int;
        for (final item in items) {
          final variantClause =
              item.variantId == null ? 'variant_id IS NULL' : 'variant_id = ?';
          final variantArgs = item.variantId == null
              ? <Object?>[countId, item.productId]
              : <Object?>[countId, item.productId, item.variantId];
          final counted = await txn.query(
            'stock_count_lines',
            where:
                'count_id = ? AND product_id = ? AND $variantClause AND counted_qty IS NOT NULL',
            whereArgs: variantArgs,
            limit: 1,
          );
          if (counted.isNotEmpty) {
            throw StateError('This item is frozen during stocktake');
          }
        }
      }
      double portionFactor(SaleItem item, double containerMl) =>
          DatabaseHelper.portionFactor(item, containerMl);

      final stockByProduct = <int, double>{};
      final reservedByProduct = <int, double>{};
      final containerMlByProduct = <int, double>{};
      final taxClassByProduct = <int, String>{};
      final trackExpiryByProduct = <int, bool>{};
      for (final productId in items.map((it) => it.productId).toSet()) {
        final current = await txn.query('products',
            where: 'id = ?', whereArgs: [productId], limit: 1);
        if (current.isEmpty) {
          final missing = items.firstWhere((it) => it.productId == productId);
          throw StateError('Product not found: ${missing.productName}');
        }
        stockByProduct[productId] =
            (current.first['stock_qty'] as num).toDouble();
        reservedByProduct[productId] =
            (current.first['reserved_qty'] as num?)?.toDouble() ?? 0;
        containerMlByProduct[productId] =
            (current.first['bottle_ml'] as num?)?.toDouble() ?? 0;
        taxClassByProduct[productId] =
            current.first['tax_class'] as String? ?? 'standard';
        trackExpiryByProduct[productId] =
            (current.first['track_expiry'] as num?)?.toInt() == 1;
      }

      final variantRowsById = <int, Map<String, dynamic>>{};
      final variantProducts = <int>{};
      for (final variantId
          in items.map((it) => it.variantId).whereType<int>().toSet()) {
        final variantRows = await txn.query('product_variants',
            where: 'id = ?', whereArgs: [variantId], limit: 1);
        if (variantRows.isEmpty) {
          final offending = items.firstWhere((it) => it.variantId == variantId);
          throw StateError('Variant not found: ${offending.productName}');
        }
        variantRowsById[variantId] = variantRows.first;
        variantProducts.add(variantRows.first['product_id'] as int);
      }

      final variantUnitsByProduct = <int, double>{};
      final directUnitsByProduct = <int, double>{};
      final requiredByVariant = <int, double>{};
      final ownReservedByVariant = <int, double>{};
      final ownReservedByProduct = <int, double>{};
      if (laybyId != null) {
        for (final row in laybyItemRows) {
          final units = (row['qty'] as num).toDouble();
          final variant = (row['variant_id'] as num?)?.toInt();
          if (variant != null) {
            ownReservedByVariant[variant] =
                (ownReservedByVariant[variant] ?? 0) + units;
          } else {
            final product = (row['product_id'] as num).toInt();
            ownReservedByProduct[product] =
                (ownReservedByProduct[product] ?? 0) + units;
          }
        }
      }
      for (final item in items) {
        final units = item.qty *
            portionFactor(item, containerMlByProduct[item.productId]!);
        final variantId = item.variantId;
        if (variantId == null) {
          directUnitsByProduct[item.productId] =
              (directUnitsByProduct[item.productId] ?? 0) + units;
        } else {
          variantUnitsByProduct[item.productId] =
              (variantUnitsByProduct[item.productId] ?? 0) + units;
          requiredByVariant[variantId] =
              (requiredByVariant[variantId] ?? 0) + units;
        }
      }
      if (enforceStock) {
        for (final entry in requiredByVariant.entries) {
          final double available =
              (variantRowsById[entry.key]!['stock_qty'] as num?)?.toDouble() ??
                  0;
          final reserved = (variantRowsById[entry.key]!['reserved_qty'] as num?)
                  ?.toDouble() ??
              0;
          final own = ownReservedByVariant[entry.key] ?? 0;
          if (available - reserved + own + DatabaseHelper.volumeTolerance < entry.value) {
            final offending =
                items.firstWhere((it) => it.variantId == entry.key);
            throw StateError('Not enough stock for ${offending.productName}');
          }
        }
        for (final entry in directUnitsByProduct.entries) {
          final available = stockByProduct[entry.key]! -
              (reservedByProduct[entry.key] ?? 0) +
              (ownReservedByProduct[entry.key] ?? 0);
          if (available + DatabaseHelper.volumeTolerance < entry.value) {
            final offending =
                items.firstWhere((it) => it.productId == entry.key);
            throw StateError('Not enough stock for ${offending.productName}');
          }
        }
      }

      final batchesByProduct = <int, List<Map<String, dynamic>>>{};
      final expiryKeys = <int, double>{
        ...directUnitsByProduct,
        for (final entry in requiredByVariant.entries) -entry.key: entry.value,
      };
      final trackedProductIds = <int>{
        for (final entry in expiryKeys.entries)
          (entry.key < 0
              ? variantRowsById[-entry.key]!['product_id'] as int
              : entry.key),
      }.where((pid) => trackExpiryByProduct[pid] == true).toSet();
      final batchRowsByProduct = <int, List<Map<String, dynamic>>>{};
      if (trackedProductIds.isNotEmpty) {
        final placeholders =
            List.filled(trackedProductIds.length, '?').join(',');
        final allBatchRows = await txn.rawQuery(
          '''SELECT * FROM stock_batches
             WHERE product_id IN ($placeholders)
               AND qty_remaining > 0
               AND expires_at >= ?
             ORDER BY expires_at ASC, id ASC''',
          [...trackedProductIds, now],
        );
        for (final row in allBatchRows) {
          final pid = (row['product_id'] as num).toInt();
          (batchRowsByProduct[pid] ??= <Map<String, dynamic>>[]).add(row);
        }
      }
      for (final entry in expiryKeys.entries) {
        final productId = entry.key < 0
            ? variantRowsById[-entry.key]!['product_id'] as int
            : entry.key;
        if (trackExpiryByProduct[productId] != true) continue;
        final variantId = entry.key < 0 ? -entry.key : null;
        final batchRows = (batchRowsByProduct[productId] ?? const [])
            .where((r) => (r['variant_id'] as num?)?.toInt() == variantId)
            .toList();
        final rows = <Map<String, dynamic>>[
          for (final row in batchRows) Map<String, dynamic>.from(row),
        ];
        final available = rows.fold<double>(
            0, (sum, row) => sum + (row['qty_remaining'] as num).toDouble());
        if (available + DatabaseHelper.volumeTolerance < entry.value) {
          final offending = items.firstWhere((it) => it.productId == entry.key);
          throw StateError(
              'Not enough unexpired stock for ${offending.productName}');
        }
        batchesByProduct[entry.key] = rows;
      }

      Map<String, dynamic>? customerRow;
      if (paymentMethod == 'credit') {
        final rows = await txn.query('customers',
            where: 'id = ?', whereArgs: [customerId], limit: 1);
        if (rows.isEmpty) {
          throw StateError('Customer not found');
        }
        customerRow = rows.first;
        if ((customerRow['active'] as num?)?.toInt() != 1) {
          throw StateError('That customer is deactivated');
        }
        final int balanceBefore =
            (customerRow['balance_minor'] as num?)?.toInt() ?? 0;
        final int? ownLimit =
            (customerRow['credit_limit_minor'] as num?)?.toInt();
        final int limit = ownLimit ?? defaultLimitMinor;
        if (balanceBefore + total.minorUnits > limit &&
            creditApprovedBy == null) {
          throw StateError(
              'That sale would take ${customerRow['name'] as String} past '
              'their credit limit');
        }
      }

      final receiptNumber =
          await DatabaseHelper.instance.allocateReceiptNumber(txn, tillCode: tillCode);

      final int saleVatMinor = items.fold<int>(
        0,
        (sum, it) =>
            sum +
            vatComponentForTaxClass(
              it.total,
              ratePercent: vatRatePercent,
              taxClass: taxClassByProduct[it.productId] ?? 'standard',
            ).minorUnits,
      );
      final int saleTaxableMinor = total.minorUnits - saleVatMinor;
      final int saleCostMinor = items.fold<int>(
        0,
        (sum, item) => sum + item.unitCost.times(item.qty).minorUnits,
      );

      final saleId = await txn.insert('sales', {
        'staff_name': staffName,
        'staff_id': staffId,
        'customer_id': customerId,
        'buyer_name': customerRow?['name'],
        'buyer_tin': customerRow?['tin'],
        'total': total.minorUnits,
        'subtotal_minor': subtotal.minorUnits,
        'order_discount_minor': subtotal.minorUnits - total.minorUnits,
        'order_discount_reason_id': orderDiscountReasonId,
        'discount_approved_by': discountApprovedBy,
        'profit': saleTaxableMinor - saleCostMinor,
        'payment_method': paymentMethod,
        'payment_reference': paymentReference,
        'amount_tendered': paid.minorUnits,
        'change_given': change.minorUnits,
        'created_at': now,
        'receipt_number': receiptNumber,
        'etims_status':
            etimsPending ? EtimsStatus.pending : EtimsStatus.notRequired,
        'payment_verified': paymentVerified ? 1 : 0,
        'payment_confirmed_at': paymentVerified ? now : null,
        'vat_rate_percent': vatRatePercent,
        'vat_minor': saleVatMinor,
        'taxable_minor': saleTaxableMinor,
        'document_type': 'sale',
      });

      if (paymentMethod == 'credit' && customerRow != null) {
        final int balanceBefore =
            (customerRow['balance_minor'] as num?)?.toInt() ?? 0;
        await txn.insert('credit_ledger', <String, Object?>{
          'uuid': DatabaseHelper.newUuid(),
          'customer_id': customerId,
          'entry_type': 'charge',
          'amount_minor': total.minorUnits,
          'sale_id': saleId,
          'staff_id': staffId,
          'staff_name': staffName,
          'approved_by': creditApprovedBy,
          'created_at': now,
        });
        await txn.rawUpdate(
          'UPDATE customers SET balance_minor = ? WHERE id = ?',
          <Object?>[balanceBefore + total.minorUnits, customerId],
        );
      }

      for (final it in items) {
        final fraction = portionFactor(it, containerMlByProduct[it.productId]!);
        final int lineVatMinor = vatComponentForTaxClass(
          it.total,
          ratePercent: vatRatePercent,
          taxClass: taxClassByProduct[it.productId] ?? 'standard',
        ).minorUnits;
        final saleItemId = await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': it.productId,
          'product_name': it.productName,
          'qty': it.qty,
          'unit_price': it.unitPrice.minorUnits,
          'list_unit_price_minor':
              (it.listUnitPrice ?? it.unitPrice).minorUnits,
          'unit_cost': it.unitCost.minorUnits,
          'discount_minor': it.discount.minorUnits,
          'discount_reason_id': it.discountReasonId,
          'price_overridden': it.priceOverridden ? 1 : 0,
          'portion': it.portion,
          'portion_ml': it.portionMl,
          'variant_id': it.variantId,
          'variant_name': it.variantName,
          'pack_id': it.packId,
          'pack_qty': it.packQty,
          'tax_class': taxClassByProduct[it.productId] ?? 'standard',
          'vat_rate_bps': vatRatePercent * 100,
          'tax_rule_id': taxRuleId.trim().isEmpty ? null : taxRuleId,
          'tax_rule_version': taxRuleVersion,
          'vat_minor': lineVatMinor,
          'taxable_minor': it.total.minorUnits - lineVatMinor,
        });
        final batchKey = it.variantId == null ? it.productId : -it.variantId!;
        final batchRows = batchesByProduct[batchKey];
        if (batchRows != null) {
          double remaining = it.qty * fraction;
          for (final batch in batchRows) {
            if (remaining <= DatabaseHelper.volumeTolerance) break;
            final available = (batch['qty_remaining'] as num).toDouble();
            if (available <= DatabaseHelper.volumeTolerance) continue;
            final taken = available < remaining ? available : remaining;
            final batchId = (batch['id'] as num).toInt();
            await txn.rawUpdate(
                "UPDATE stock_batches SET qty_remaining = qty_remaining - ?, "
                "status = CASE WHEN qty_remaining - ? <= ? THEN 'depleted' ELSE 'active' END "
                'WHERE id = ?',
                [taken, taken, DatabaseHelper.qtyEpsilon, batchId]);
            await txn.insert('sale_item_batches', {
              'sale_item_id': saleItemId,
              'batch_id': batchId,
              'qty': taken,
            });
            batch['qty_remaining'] = available - taken;
            remaining -= taken;
          }
          if (remaining > DatabaseHelper.volumeTolerance) {
            throw StateError('Unexpired stock changed while recording sale');
          }
        }
        final variantId = it.variantId;
        if (variantId != null) {
          await txn.rawUpdate(
            'UPDATE product_variants SET stock_qty = MAX(0, stock_qty - ?) WHERE id = ?',
            [it.qty * fraction, variantId],
          );
        }
      }

      for (final productId in items.map((it) => it.productId).toSet()) {
        final flagRows = await txn.query('products',
            columns: ['track_variants'],
            where: 'id = ?',
            whereArgs: [productId],
            limit: 1);
        final tracks = flagRows.isNotEmpty &&
            ((flagRows.first['track_variants'] as num?)?.toInt() ?? 0) == 1;
        final double directUnits = directUnitsByProduct[productId] ?? 0;
        if (tracks) {
          await txn.rawUpdate(
            'UPDATE products SET stock_qty = MAX(0, (SELECT COALESCE(SUM(stock_qty), 0) '
            'FROM product_variants WHERE product_id = ? AND active = 1) - ?), '
            'updated_at = ? WHERE id = ?',
            [productId, directUnits, now, productId],
          );
        } else {
          final double variantUnits = variantUnitsByProduct[productId] ?? 0;
          await txn.rawUpdate(
            'UPDATE products SET stock_qty = MAX(0, stock_qty - ?), updated_at = ? WHERE id = ?',
            [directUnits + variantUnits, now, productId],
          );
        }
      }

      for (final it in items) {
        final fraction = portionFactor(it, containerMlByProduct[it.productId]!);
        final double units = it.qty * fraction;
        final variantId = it.variantId;
        if (variantId != null) {
          final double balance =
              await DatabaseHelper.instance.variantBalanceAfter(txn, variantId);
          await DatabaseHelper.instance.writeStockMovement(
            txn: txn,
            productId: it.productId,
            variantId: variantId,
            type: StockMovementType.sale,
            qtyDelta: -units,
            unitCostMinor: it.unitCost.minorUnits,
            referenceType: 'sale',
            referenceId: saleId,
            staffId: staffId,
            staffName: staffName,
            balanceAfter: balance,
            createdAt: now,
          );
        }
        final double productBalance =
            await DatabaseHelper.instance.productBalanceAfter(txn, it.productId);
        await DatabaseHelper.instance.writeStockMovement(
          txn: txn,
          productId: it.productId,
          variantId: null,
          type: StockMovementType.sale,
          qtyDelta: -units,
          unitCostMinor: it.unitCost.minorUnits,
          referenceType: 'sale',
          referenceId: saleId,
          staffId: staffId,
          staffName: staffName,
          balanceAfter: productBalance,
          createdAt: now,
        );
      }

      for (final tender in tenderRows) {
        final tendered = tender.tendered ?? tender.amount;
        final tenderChange = tendered - tender.amount;
        await txn.insert('sale_payments', {
          'uuid': DatabaseHelper.newUuid(),
          'sale_id': saleId,
          'method': tender.method,
          'amount_minor': tender.amount.minorUnits,
          'tendered_minor': tendered.minorUnits,
          'change_minor': tenderChange.minorUnits,
          'reference': tender.reference,
          'status': tender.status,
          'pending_payment_id': null,
          'created_at': now,
        });
      }

      if (etimsPending) {
        await txn.insert('pending_etims', {
          'sale_id': saleId,
          'receipt_number': receiptNumber,
          'attempts': 0,
          'created_at': now,
          'updated_at': now,
          'document_type': 'sale',
        });
      }
      await FinanceRepository.instance.appendFinancialEventInTransaction(
        txn: txn,
        eventType: 'sale',
        sourceType: 'sale',
        sourceId: saleId,
        occurredAtUtc: eventAtUtc,
        revenueMinor: saleTaxableMinor,
        cashInMinor: paymentMethod == 'credit' || paymentMethod == 'layby'
            ? 0
            : tenders == null
                ? (paymentMethod == 'exchange_credit' ? 0 : total.minorUnits)
                : sumMoney(tenderRows
                    .where((tender) => tender.method != 'exchange_credit')
                    .map((tender) => tender.amount)).minorUnits,
        cogsMinor: saleCostMinor,
        taxCollectedMinor: saleVatMinor,
        receivableDeltaMinor: paymentMethod == 'credit' ? total.minorUnits : 0,
        inventoryDeltaMilliunits: items.fold<int>(
          0,
          (sum, item) =>
              sum +
              (item.qty *
                          portionFactor(
                            item,
                            containerMlByProduct[item.productId]!,
                          ) *
                      1000)
                  .round() *
              -1,
        ),
        metadata: <String, Object?>{
          'payment_method': paymentMethod,
          'payment_verified': paymentVerified,
          'line_count': items.length,
        },
      );
      if (laybyId != null) {
        for (final item in items) {
          final units = item.qty *
              portionFactor(item, containerMlByProduct[item.productId]!);
          if (item.variantId != null) {
            await txn.rawUpdate(
              'UPDATE product_variants SET reserved_qty = MAX(0, reserved_qty - ?) WHERE id = ?',
              [units, item.variantId],
            );
          }
          await txn.rawUpdate(
            'UPDATE products SET reserved_qty = MAX(0, reserved_qty - ?) WHERE id = ?',
            [units, item.productId],
          );
        }
        await txn.update(
            'laybys',
            {
              'status': LaybyStatus.completed.wire,
              'sale_id': saleId,
              'completed_at': now,
              'synced_to_backend': 0,
            },
            where: 'id = ?',
            whereArgs: [laybyId]);
        await FinanceRepository.instance.appendFinancialEventInTransaction(
          txn: txn,
          eventType: 'layby_complete',
          sourceType: 'layby',
          sourceId: laybyId,
          occurredAtUtc: eventAtUtc,
          customerDepositDeltaMinor: -total.minorUnits,
          metadata: {'sale_id': saleId},
        );
      }
      return saleId;
    }

    return write(txn);
  }

  // ── Public methods ─────────────────────────────────────────────────

  Future<int> recordSale({
    required String staffName,
    required List<SaleItem> items,
    List<SaleTender>? tenders,
    bool enforceStock = true,
    String paymentMethod = 'cash',
    String? paymentReference,
    Money? amountTendered,
    int? staffId,
    bool etimsPending = false,
    bool paymentVerified = true,
    int? customerId,
    int? creditApprovedBy,
    int? discountApprovedBy,
    int? orderDiscountReasonId,
    int? laybyId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    // Read settings BEFORE opening the transaction to avoid sqflite_ffi
    // deadlocks on reads inside a write transaction.
    final tillCode = await DatabaseHelper.instance.tillCodeFromExecutor(db);
    final vatRatePercent =
        await DatabaseHelper.instance.vatRateFromExecutor(db);
    final taxRuleId = await DatabaseHelper.instance
        .settingFromExecutor(db, DatabaseHelper.settingTaxRuleId);
    final taxRuleVersion = int.tryParse(
        await DatabaseHelper.instance
                .settingFromExecutor(db, DatabaseHelper.settingTaxRuleVersion) ??
            '');
    final defaultLimitMinor =
        await DatabaseHelper.instance.creditDefaultLimitFromExecutor(db);
    return db.transaction<int>((txn) => recordSaleInTransaction(
      txn,
      staffName: staffName,
      items: items,
      tenders: tenders,
      enforceStock: enforceStock,
      paymentMethod: paymentMethod,
      paymentReference: paymentReference,
      amountTendered: amountTendered,
      staffId: staffId,
      etimsPending: etimsPending,
      paymentVerified: paymentVerified,
      customerId: customerId,
      creditApprovedBy: creditApprovedBy,
      discountApprovedBy: discountApprovedBy,
      orderDiscountReasonId: orderDiscountReasonId,
      laybyId: laybyId,
      tillCode: tillCode,
      vatRatePercent: vatRatePercent,
      taxRuleId: taxRuleId ?? '',
      taxRuleVersion: taxRuleVersion ?? 0,
      defaultLimitMinor: defaultLimitMinor,
    ));
  }

  /// Records an Open-profile quick sale within [txn]. Never opens its own
  /// transaction.
  Future<int> recordOpenQuickSaleInTransaction(Transaction txn, {
    required Money amount,
    required String paymentMethod,
    required String staffName,
    int? staffId,
    String? paymentReference,
    Money? costAmount,
    bool trackCost = false,
  }) async {
    if (amount.minorUnits <= 0) {
      throw StateError('A quick sale must be more than zero');
    }
    if (!<String>{'cash', 'mpesa', 'bank_transfer'}.contains(paymentMethod)) {
      throw StateError('Unsupported quick-sale payment method');
    }
    final now = DateTime.now().toIso8601String();
    final saleId = await txn.insert('sales', <String, Object?>{
      'staff_name': staffName.trim().isEmpty ? 'Open business' : staffName,
      'staff_id': staffId,
      'total': amount.minorUnits,
      'profit':
          (trackCost ? (amount.minorUnits - (costAmount?.minorUnits ?? 0)) : 0),
      'payment_method': paymentMethod,
      'payment_reference': paymentReference,
      'amount_tendered': amount.minorUnits,
      'change_given': 0,
      'created_at': now,
      'vat_rate_percent': 0,
      'vat_minor': 0,
      'taxable_minor': 0,
      'document_type': 'sale',
      'etims_status': EtimsStatus.notRequired,
      'payment_verified': 1,
    });
    await txn.insert('sale_payments', <String, Object?>{
      'uuid': DatabaseHelper.newUuid(),
      'sale_id': saleId,
      'method': paymentMethod,
      'amount_minor': amount.minorUnits,
      'tendered_minor': amount.minorUnits,
      'change_minor': 0,
      'reference': paymentReference,
      'status': 'confirmed',
      'created_at': now,
    });
    await FinanceRepository.instance.appendFinancialEventInTransaction(
      txn: txn,
      eventType: 'sale',
      sourceType: 'sale',
      sourceId: saleId,
      occurredAtUtc: DateTime.parse(now).toUtc().toIso8601String(),
      revenueMinor: amount.minorUnits,
      cashInMinor: amount.minorUnits,
      metadata: <String, Object?>{
        'profile': ShopProfile.open.wireValue,
        'open_quick_sale': true,
        'cost_coverage': 'unrecorded',
        'tax_mode': 'off',
      },
    );
    return saleId;
  }

  /// Records an Open-profile quick sale, opening its own transaction.
  Future<int> recordOpenQuickSale({
    required Money amount,
    required String paymentMethod,
    required String staffName,
    int? staffId,
    String? paymentReference,
    Money? costAmount,
    bool trackCost = false,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction<int>((txn) => recordOpenQuickSaleInTransaction(
      txn,
      amount: amount,
      paymentMethod: paymentMethod,
      staffName: staffName,
      staffId: staffId,
      paymentReference: paymentReference,
      costAmount: costAmount,
      trackCost: trackCost,
    ));
  }

  Future<List<Map<String, dynamic>>> getSales({
    int? staffId,
    String? from,
    String? to,
    int limit = 200,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'sales',
      where: (staffId != null ? 'staff_id = ?' : null),
      whereArgs: staffId != null ? [staffId] : null,
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }
}
