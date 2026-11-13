import 'package:sqflite/sqflite.dart';

import '../../../db/database_helper.dart';
import '../../../models/credit.dart';
import '../../../models/models.dart';
import '../../../models/stock_movement.dart';
import 'finance_repository.dart';
import '../../../utils/money.dart';

/// Repository for customers and credit ledger.
///
/// Delegates to [DatabaseHelper] for now. Transaction-aware variants accept an
/// open [Transaction] so a credit sale and its ledger entry commit together.
class CustomerRepository {
  CustomerRepository._();
  static final CustomerRepository instance = CustomerRepository._();

  /// Creates (or verifies) the `customers` and `credit_ledger` tables.
  ///
  /// Mirrors `_createCreditTables` so fresh installs and upgraded tills match.
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        phone TEXT,
        tin TEXT,
        notes TEXT,
        credit_limit_minor INTEGER,
        balance_minor INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers (name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers (phone)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS credit_ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        customer_id INTEGER NOT NULL,
        entry_type TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        sale_id INTEGER,
        return_id INTEGER,
        payment_method TEXT,
        reference TEXT,
        shift_id INTEGER,
        staff_id INTEGER,
        staff_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_credit_ledger_customer ON credit_ledger (customer_id, created_at)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS credit_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_entry_id INTEGER NOT NULL,
        charge_entry_id INTEGER NOT NULL,
        amount_minor INTEGER NOT NULL,
        FOREIGN KEY (payment_entry_id) REFERENCES credit_ledger (id),
        FOREIGN KEY (charge_entry_id) REFERENCES credit_ledger (id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_credit_allocations_payment '
        'ON credit_allocations (payment_entry_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_credit_allocations_charge '
        'ON credit_allocations (charge_entry_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS sale_returns (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL,
      kind TEXT NOT NULL DEFAULT 'refund',
      reason TEXT NOT NULL,
      total INTEGER NOT NULL DEFAULT 0,
      vat_total INTEGER NOT NULL DEFAULT 0,
      profit INTEGER NOT NULL DEFAULT 0,
      refund_method TEXT NOT NULL DEFAULT 'cash',
      payment_reference TEXT,
      shift_id INTEGER,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      synced_to_backend INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_returns_sale ON sale_returns (sale_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS sale_return_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      return_id INTEGER NOT NULL,
      sale_item_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      qty REAL NOT NULL,
      unit_price INTEGER NOT NULL,
      unit_cost INTEGER NOT NULL,
      refund_minor INTEGER NOT NULL DEFAULT 0,
      vat_minor INTEGER NOT NULL DEFAULT 0,
      portion TEXT NOT NULL DEFAULT 'full',
      portion_ml INTEGER NOT NULL DEFAULT 0,
      restock INTEGER NOT NULL DEFAULT 1,
      restock_reason TEXT,
      FOREIGN KEY (return_id) REFERENCES sale_returns (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_return_items_return ON sale_return_items (return_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS sale_return_refunds (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      return_id INTEGER NOT NULL,
      sale_payment_id INTEGER,
      method TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      reference TEXT,
      FOREIGN KEY (return_id) REFERENCES sale_returns (id) ON DELETE CASCADE,
      FOREIGN KEY (sale_payment_id) REFERENCES sale_payments (id) ON DELETE SET NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_return_refunds_return ON sale_return_refunds (return_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS receive_drafts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      staff_id INTEGER UNIQUE,
      payload TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS laybys (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      customer_id INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'open',
      total_minor INTEGER NOT NULL,
      paid_minor INTEGER NOT NULL DEFAULT 0,
      due_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      sale_id INTEGER,
      completed_at TEXT,
      cancelled_at TEXT,
      synced_to_backend INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (customer_id) REFERENCES customers (id),
      FOREIGN KEY (sale_id) REFERENCES sales (id)
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_laybys_status_due ON laybys (status, due_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_laybys_customer ON laybys (customer_id, created_at)');

    await db.execute('''CREATE TABLE IF NOT EXISTS layby_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      layby_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      variant_id INTEGER,
      product_name TEXT NOT NULL,
      variant_name TEXT NOT NULL DEFAULT '',
      qty REAL NOT NULL,
      unit_price_minor INTEGER NOT NULL,
      unit_cost_minor INTEGER NOT NULL,
      discount_minor INTEGER NOT NULL DEFAULT 0,
      total_minor INTEGER NOT NULL,
      FOREIGN KEY (layby_id) REFERENCES laybys (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_layby_items_layby ON layby_items (layby_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS layby_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      layby_id INTEGER NOT NULL,
      method TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      direction TEXT NOT NULL DEFAULT 'in',
      reference TEXT,
      created_at TEXT NOT NULL,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      FOREIGN KEY (layby_id) REFERENCES laybys (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_layby_payments_layby ON layby_payments (layby_id, created_at)');

    await db.execute('''CREATE TABLE IF NOT EXISTS exchanges (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      original_sale_id INTEGER NOT NULL,
      return_id INTEGER,
      replacement_sale_id INTEGER,
      status TEXT NOT NULL DEFAULT 'completed',
      returned_total_minor INTEGER NOT NULL,
      replacement_total_minor INTEGER NOT NULL,
      difference_minor INTEGER NOT NULL DEFAULT 0,
      difference_direction TEXT NOT NULL DEFAULT 'even',
      reason TEXT NOT NULL,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      synced_to_backend INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (original_sale_id) REFERENCES sales (id),
      FOREIGN KEY (return_id) REFERENCES sale_returns (id),
      FOREIGN KEY (replacement_sale_id) REFERENCES sales (id)
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_exchanges_original_sale '
        'ON exchanges (original_sale_id, created_at)');
  }

  // ── Transaction-aware variants ─────────────────────────────────────

  Future<int> upsertCustomerInTransaction(Transaction txn, Customer customer) async {
    final name = customer.name.trim();
    if (name.isEmpty) {
      throw StateError('Enter a name');
    }
    if (customer.phone != null && customer.phone!.isNotEmpty) {
      if (normaliseKenyanPhone(customer.phone) == null &&
          normaliseKenyanPhone(customer.phoneDisplay ?? customer.phone) ==
              null &&
          !(customer.phone!.startsWith('+'))) {
        throw StateError('That phone number is not a Kenyan number we can use');
      }
    }
    final id = customer.id;
    final clash = await txn.rawQuery(
      'SELECT id FROM customers WHERE active = 1 AND '
      'LOWER(name) = LOWER(?) ${id != null ? 'AND id != ?' : ''} LIMIT 1',
      id == null ? [name] : [name, id],
    );
    if (clash.isNotEmpty) {
      throw StateError('Another active customer already has that name');
    }
    final phone = customer.phone == null || customer.phone!.isEmpty
        ? null
        : DatabaseHelper.canonicalPhone(customer.phone!);
    if (phone != null) {
      final phoneClash = await txn.rawQuery(
        'SELECT id FROM customers WHERE active = 1 AND phone = ? '
        '${id != null ? 'AND id != ?' : ''} LIMIT 1',
        id == null ? [phone] : [phone, id],
      );
      if (phoneClash.isNotEmpty) {
        throw StateError('Another active customer already has that number');
      }
    }

    final row = customer.toMap()
      ..['name'] = name
      ..['phone'] = phone;
    if (id == null) {
      return txn.insert('customers', row..remove('id'));
    }
    final existing = await txn.query('customers',
        columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isEmpty) {
      throw StateError('Customer not found');
    }
    await txn.update('customers', row..remove('id'),
        where: 'id = ?', whereArgs: [id]);
    return id;
  }

  // ── Public methods ─────────────────────────────────────────────────

  Future<int> upsertCustomer(Customer customer) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction<int>((txn) => upsertCustomerInTransaction(txn, customer));
  }

  Future<Customer?> getCustomer(int id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  Future<List<Map<String, dynamic>>> getCustomers({bool activeOnly = true}) async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'customers',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'name',
    );
  }

  /// Returns goods within [txn]. Never opens its own transaction.
  Future<int> recordReturnInTransaction(Transaction txn, {
    required Sale sale,
    required List<ReturnLineDraft> lines,
    required String reason,
    String kind = 'refund',
    String refundMethod = 'cash',
    String? paymentReference,
    required String staffName,
    int? staffId,
  }) async {
    if (lines.isEmpty) {
      throw StateError('A return must contain at least one line');
    }
    if (reason.trim().isEmpty) {
      throw StateError('A return must say why');
    }
    if (sale.id == null) {
      throw StateError('That sale cannot be returned');
    }

    // What has already come back, per sale line.
    final previous = await txn.rawQuery(
      'SELECT sale_item_id, COALESCE(SUM(qty), 0) AS returned_qty '
      'FROM sale_return_items WHERE sale_item_id IN '
      '(${List.filled(lines.length, '?').join(',')}) '
      'GROUP BY sale_item_id',
      lines.map((ReturnLineDraft l) => l.saleItemId).toList(),
    );
    final returnedByItem = <int, double>{
      for (final row in previous)
        row['sale_item_id'] as int: (row['returned_qty'] as num).toDouble(),
    };

    // The sale's own lines, so the returned quantity can be checked against
    // what was sold and the refund scaled by what was sold.
    final saleItems = <int, SaleItem>{
      for (final SaleItem item in sale.items)
        if (item.id != null) item.id!: item,
    };

    // A mobile-money sale whose payment was never confirmed cannot be
    // returned: the money may never have arrived.
    if (sale.paymentMethod == 'mpesa' &&
        !await paymentIsVerified(txn, sale.id!)) {
      throw StateError(
        'That sale was never confirmed as paid, so it cannot be returned',
      );
    }

    // A cash refund needs a drawer to take the money out of.
    final bool isCashRefund = refundMethod == 'cash';
    int? openShiftId;
    if (isCashRefund) {
      final shift = await txn.query(
        'shifts',
        where: 'status = ?',
        whereArgs: ['open'],
        orderBy: 'start_time DESC',
        limit: 1,
      );
      if (shift.isEmpty) {
        throw StateError(
          'Open a shift before giving cash back, so the drawer can be counted',
        );
      }
      openShiftId = shift.first['id'] as int;
    }

    int totalMinor = 0;
    int vatMinor = 0;
    int profitMinor = 0;
    int restockedCostMinor = 0;
    int writtenOffCostMinor = 0;
    int restockedMilliunits = 0;
    final now = DateTime.now().toIso8601String();

    final containerMlByProduct = <int, double>{};

    for (final ReturnLineDraft draft in lines) {
      final SaleItem? sold = saleItems[draft.saleItemId];
      if (sold == null) {
        throw StateError('That line is not on the sale');
      }
      final double soldQty = sold.qty;
      final double already = returnedByItem[draft.saleItemId] ?? 0;
      if (draft.qty <= 0) {
        throw StateError('A returned quantity must be more than zero');
      }
      if (already + draft.qty > soldQty + DatabaseHelper.qtyEpsilon) {
        throw StateError(
          'More was returned than was sold on that line',
        );
      }

      // The refund for the line: the line total scaled by the returned
      // fraction, rounded half-up.
      final int lineTotal = sold.total.minorUnits;
      final int refund = DatabaseHelper.roundHalfUp(lineTotal * (draft.qty / soldQty));
      final int soldVat = sold.vatMinor ?? 0;
      final int lineVat = DatabaseHelper.roundHalfUp(soldVat * (draft.qty / soldQty));
      totalMinor += refund;
      vatMinor += lineVat;
      profitMinor += DatabaseHelper.roundHalfUp(
        sold.unitCost.minorUnits * soldQty * (draft.qty / soldQty),
      );

      containerMlByProduct[sold.productId] ??= ((await txn.query(
            'products',
            columns: ['bottle_ml'],
            where: 'id = ?',
            whereArgs: [sold.productId],
            limit: 1,
          ))
                  .firstOrNull?['bottle_ml'] as num?)
              ?.toDouble() ??
          0;

      // The goods: back on the shelf, or written off.
      final double units = draft.qty *
          DatabaseHelper.portionFactor(sold, containerMlByProduct[sold.productId]!);
      final int returnCostMinor = DatabaseHelper.roundHalfUp(
        sold.unitCost.minorUnits * draft.qty,
      );
      if (draft.restock) {
        restockedCostMinor += returnCostMinor;
        restockedMilliunits += (units * 1000).round();
        final double balance =
            await DatabaseHelper.instance.productBalanceAfter(txn, sold.productId);
        await DatabaseHelper.instance.writeStockMovement(
          txn: txn,
          productId: sold.productId,
          variantId: sold.variantId,
          type: StockMovementType.saleReturn,
          qtyDelta: units,
          unitCostMinor: sold.unitCost.minorUnits,
          referenceType: 'sale_return',
          referenceId: null,
          staffId: staffId,
          staffName: staffName,
          note: 'Returned',
          balanceAfter: balance,
          createdAt: now,
        );
        // The COUNT, in the same transaction as the movement.
        await restoreStockCount(
          txn,
          productId: sold.productId,
          variantId: sold.variantId,
          units: units,
        );
        // Put a restocked return back into the exact batches it came from.
        final batchLinks = await txn.query(
          'sale_item_batches',
          where: 'sale_item_id = ?',
          whereArgs: [draft.saleItemId],
          orderBy: 'batch_id ASC',
        );
        if (batchLinks.isNotEmpty) {
          for (final link in batchLinks) {
            final soldFromBatch = (link['qty'] as num).toDouble();
            final restore = soldFromBatch * (draft.qty / soldQty);
            await txn.rawUpdate(
              'UPDATE stock_batches SET qty_remaining = qty_remaining + ? '
              'WHERE id = ?',
              [restore, link['batch_id']],
            );
          }
        }
      } else {
        writtenOffCostMinor += returnCostMinor;
        final double balance =
            await DatabaseHelper.instance.productBalanceAfter(txn, sold.productId);
        await DatabaseHelper.instance.writeStockMovement(
          txn: txn,
          productId: sold.productId,
          variantId: sold.variantId,
          type: StockMovementType.writeoff,
          qtyDelta: -units,
          unitCostMinor: sold.unitCost.minorUnits,
          referenceType: 'sale_return',
          referenceId: null,
          staffId: staffId,
          staffName: staffName,
          note: draft.restockReason ?? 'Written off',
          balanceAfter: balance,
          createdAt: now,
        );
      }
    }

    final int returnId = await txn.insert('sale_returns', {
      'sale_id': sale.id,
      'kind': kind,
      'reason': reason.trim(),
      'total': totalMinor,
      'vat_total': vatMinor,
      'profit': profitMinor,
      'refund_method': refundMethod,
      'payment_reference': paymentReference,
      'shift_id': openShiftId,
      'staff_id': staffId,
      'staff_name': staffName,
      'created_at': now,
      'synced_to_backend': 0,
    });

    // A split refund follows the original payment weights. Integer
    // largest-remainder allocation makes the rows sum to the exact refund,
    // including when the amount cannot be divided evenly into cents.
    final paymentRows = await txn.query(
      'sale_payments',
      where: 'sale_id = ? AND status != ? AND amount_minor > 0',
      whereArgs: [sale.id, 'pending'],
      orderBy: 'id ASC',
    );
    final eligiblePayments = paymentRows.isEmpty
        ? <Map<String, dynamic>>[
            <String, dynamic>{
              'id': null,
              'method': refundMethod,
              'amount_minor': totalMinor,
              'reference': paymentReference,
            },
          ]
        : paymentRows;
    final allocations = largestRemainderAllocation(
      totalMinor,
      eligiblePayments
          .map((row) => (row['amount_minor'] as num).toInt())
          .toList(),
    );
    for (var i = 0; i < eligiblePayments.length; i++) {
      final amount = allocations[i];
      if (amount == 0) continue;
      final payment = eligiblePayments[i];
      await txn.insert('sale_return_refunds', {
        'return_id': returnId,
        'sale_payment_id': payment['id'],
        'method': payment['method'] as String? ?? refundMethod,
        'amount_minor': amount,
        'reference': payment['reference'] as String? ?? paymentReference,
      });
    }

    // A credit-account sale REFUNDS to the account by default (spec 7.5.4):
    // the reversal is a return_credit entry against the customer's ledger,
    // in the same transaction as the return — never a drawer action,
    // never an edit.
    if (refundMethod == 'credit_to_account') {
      final customerRows = await txn.query(
        'sales',
        columns: <String>['customer_id'],
        where: 'id = ?',
        whereArgs: [sale.id],
        limit: 1,
      );
      final int? customerId =
          (customerRows.first['customer_id'] as num?)?.toInt();
      if (customerId == null) {
        throw StateError(
            'That sale was not taken on account, so there is no account to refund');
      }
      await txn.insert('credit_ledger', <String, Object?>{
        'uuid': DatabaseHelper.newUuid(),
        'customer_id': customerId,
        'entry_type': 'return_credit',
        'amount_minor': -totalMinor,
        'sale_id': sale.id,
        'return_id': returnId,
        'staff_id': staffId,
        'staff_name': staffName,
        'created_at': now,
      });
      await txn.rawUpdate(
        'UPDATE customers SET balance_minor = balance_minor - ? '
        'WHERE id = ?',
        <Object?>[totalMinor, customerId],
      );
    }

    for (final ReturnLineDraft draft in lines) {
      final SaleItem sold = saleItems[draft.saleItemId]!;
      final int lineTotal = sold.total.minorUnits;
      await txn.insert('sale_return_items', {
        'return_id': returnId,
        'sale_item_id': draft.saleItemId,
        'product_id': sold.productId,
        'product_name': sold.productName,
        'qty': draft.qty,
        'unit_price': sold.unitPrice.minorUnits,
        'unit_cost': sold.unitCost.minorUnits,
        'refund_minor': DatabaseHelper.roundHalfUp(lineTotal * (draft.qty / sold.qty)),
        'vat_minor': DatabaseHelper.roundHalfUp(
          (sold.vatMinor ?? 0) * (draft.qty / sold.qty),
        ),
        'portion': sold.portion,
        'portion_ml': sold.portionMl,
        'restock': draft.restock ? 1 : 0,
        'restock_reason': draft.restockReason,
      });
    }

    await FinanceRepository.instance.appendFinancialEventInTransaction(
      txn: txn,
      eventType: 'refund',
      sourceType: 'sale_return',
      sourceId: returnId,
      occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
      revenueMinor: -(totalMinor - vatMinor),
      cashOutMinor: refundMethod == 'credit_to_account' ||
              refundMethod == 'exchange_credit'
          ? 0
          : totalMinor,
      cogsMinor: -restockedCostMinor,
      operatingExpenseMinor: writtenOffCostMinor,
      taxCollectedMinor: -vatMinor,
      receivableDeltaMinor:
          refundMethod == 'credit_to_account' ? -totalMinor : 0,
      inventoryDeltaMilliunits: restockedMilliunits,
      metadata: <String, Object?>{
        'sale_id': sale.id,
        'refund_method': refundMethod,
        'line_count': lines.length,
      },
    );

    return returnId;
  }

  /// Returns goods, opening its own transaction unless [existingTransaction]
  /// is provided.
  Future<int> recordReturn({
    required Sale sale,
    required List<ReturnLineDraft> lines,
    required String reason,
    String kind = 'refund',
    String refundMethod = 'cash',
    String? paymentReference,
    required String staffName,
    int? staffId,
    DatabaseExecutor? existingTransaction,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final txn = existingTransaction as Transaction?;
    if (txn != null) {
      return recordReturnInTransaction(
        txn,
        sale: sale,
        lines: lines,
        reason: reason,
        kind: kind,
        refundMethod: refundMethod,
        paymentReference: paymentReference,
        staffName: staffName,
        staffId: staffId,
      );
    }
    return db.transaction<int>((txn) => recordReturnInTransaction(
      txn,
      sale: sale,
      lines: lines,
      reason: reason,
      kind: kind,
      refundMethod: refundMethod,
      paymentReference: paymentReference,
      staffName: staffName,
      staffId: staffId,
    ));
  }

  /// Puts [units] back on the shelf, in the same transaction as the movement.
  Future<void> restoreStockCount(Transaction txn, {
    required int productId,
    int? variantId,
    required double units,
  }) async {
    final String now = DateTime.now().toIso8601String();
    if (variantId != null) {
      await txn.rawUpdate(
        'UPDATE product_variants SET stock_qty = MAX(0, stock_qty + ?) WHERE id = ?',
        [units, variantId],
      );
    }
    final flagRows = await txn.query(
      'products',
      columns: <String>['track_variants'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    final bool tracks = flagRows.isNotEmpty &&
        ((flagRows.first['track_variants'] as num?)?.toInt() ?? 0) == 1;
    if (tracks) {
      await txn.rawUpdate(
        'UPDATE products SET stock_qty = (SELECT COALESCE(SUM(stock_qty), 0) '
        'FROM product_variants WHERE product_id = ? AND active = 1), '
        'updated_at = ? WHERE id = ?',
        [productId, now, productId],
      );
    } else {
      await txn.rawUpdate(
        'UPDATE products SET stock_qty = MAX(0, stock_qty + ?), updated_at = ? '
        'WHERE id = ?',
        [units, now, productId],
      );
    }
  }

  /// Whether the money for this sale ever arrived.
  Future<bool> paymentIsVerified(Transaction txn, int saleId) async {
    final rows = await txn.rawQuery(
      'SELECT payment_verified FROM sales WHERE id = ? LIMIT 1',
      [saleId],
    );
    if (rows.isEmpty) return true;
    return ((rows.first['payment_verified'] as num?)?.toInt() ?? 1) == 1;
  }
}
