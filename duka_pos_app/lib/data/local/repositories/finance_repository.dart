import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:crypto/crypto.dart' show sha256;

import '../../../db/database_helper.dart';
import '../../../models/financial_event.dart';
import '../../../models/models.dart';
import '../../../models/stock_movement.dart';
import 'customer_repository.dart';
import '../../../utils/money.dart';

/// Repository for finance: expenses, payments, ledger.
///
/// Manages persistence of expense records, expense payments, and financial
/// events. Operations that touch multiple tables (e.g. recording an expense
/// and appending its financial event together) use transaction-aware variants
/// so the operation is atomic.
class FinanceRepository {
  FinanceRepository._();
  static final FinanceRepository instance = FinanceRepository._();

  /// Creates (or verifies) the finance tables: `expense_categories`, `expenses`,
  /// `till_movements` and `expense_payments`.
  ///
  /// Mirrors `_createExpenseTables`/`_createExpensePaymentsTable` so fresh
  /// installs and upgraded tills match. Default expense categories are seeded
  /// on first creation.
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expense_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        active INTEGER NOT NULL DEFAULT 1,
        system INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shift_id INTEGER,
        category_id INTEGER NOT NULL,
        amount_minor INTEGER NOT NULL,
        paid_from TEXT NOT NULL DEFAULT 'till_cash',
        note TEXT,
        photo_path TEXT,
        staff_id INTEGER,
        approved_by INTEGER,
        staff_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'posted',
        synced_to_backend INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_expenses_shift ON expenses (shift_id, created_at)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS till_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shift_id INTEGER NOT NULL,
        movement_type TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        note TEXT,
        staff_id INTEGER,
        staff_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'posted',
        synced_to_backend INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_till_movements_shift ON till_movements (shift_id, created_at)');
    await db.execute('''CREATE TABLE IF NOT EXISTS expense_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      expense_id INTEGER NOT NULL,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      payment_method TEXT NOT NULL,
      reference TEXT,
      shift_id INTEGER,
      created_at TEXT NOT NULL,
      FOREIGN KEY (expense_id) REFERENCES expenses (id)
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_expense_payments_expense '
        'ON expense_payments (expense_id, created_at)');

    final existing = await db.query('expense_categories', limit: 1);
    if (existing.isEmpty) {
      const categories = <String>[
        'Rent',
        'Electricity and water',
        'Transport',
        'Wages',
        'Supplies',
        'Airtime and data',
        'Licences and fees',
        'Bad debts',
        'Other',
      ];
      for (final name in categories) {
        await db.insert(
          'expense_categories',
          {'name': name, 'active': 1, 'system': 1},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    await db.execute('''CREATE TABLE IF NOT EXISTS financial_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      event_type TEXT NOT NULL,
      source_type TEXT NOT NULL,
      source_id INTEGER,
      occurred_at_utc TEXT NOT NULL,
      revenue_minor INTEGER NOT NULL DEFAULT 0,
      cash_in_minor INTEGER NOT NULL DEFAULT 0,
      cash_out_minor INTEGER NOT NULL DEFAULT 0,
      cogs_minor INTEGER NOT NULL DEFAULT 0,
      operating_expense_minor INTEGER NOT NULL DEFAULT 0,
      tax_collected_minor INTEGER NOT NULL DEFAULT 0,
      receivable_delta_minor INTEGER NOT NULL DEFAULT 0,
      payable_delta_minor INTEGER NOT NULL DEFAULT 0,
      customer_deposit_delta_minor INTEGER NOT NULL DEFAULT 0,
      inventory_delta_milliunits INTEGER NOT NULL DEFAULT 0,
      metadata_json TEXT NOT NULL DEFAULT '{}',
      previous_hash TEXT,
      integrity_hash TEXT NOT NULL,
      synced_to_backend INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_financial_events_occurred '
        'ON financial_events (occurred_at_utc, id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_financial_events_source '
        'ON financial_events (source_type, source_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS owner_transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      transaction_type TEXT NOT NULL,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      shift_id INTEGER,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      note TEXT,
      created_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'posted',
      synced_to_backend INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_owner_transactions_date '
        'ON owner_transactions (created_at, id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS cost_pools (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      pool_type TEXT NOT NULL CHECK (pool_type IN ('lot', 'rolling_stock', 'bale')),
      invested_minor INTEGER NOT NULL DEFAULT 0,
      recovered_minor INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'open',
      note TEXT,
      created_at TEXT NOT NULL,
      closed_at TEXT
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS cost_pool_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      pool_id INTEGER NOT NULL,
      entry_type TEXT NOT NULL,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      paid_from TEXT NOT NULL DEFAULT 'other',
      description TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (pool_id) REFERENCES cost_pools (id)
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS sale_pool_allocations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pool_id INTEGER NOT NULL,
      sale_id INTEGER NOT NULL,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      created_at TEXT NOT NULL,
      UNIQUE (pool_id, sale_id),
      FOREIGN KEY (pool_id) REFERENCES cost_pools (id)
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS drawer_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      shift_id INTEGER,
      event_type TEXT NOT NULL,
      reason TEXT,
      staff_id INTEGER,
      staff_name TEXT NOT NULL,
      sale_id INTEGER,
      approved_by TEXT,
      created_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'recorded',
      success INTEGER NOT NULL DEFAULT 0,
      synced_to_backend INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (shift_id) REFERENCES shifts (id) ON DELETE SET NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_drawer_events_created '
        'ON drawer_events (created_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_drawer_events_shift '
        'ON drawer_events (shift_id, created_at DESC)');

    await db.execute('''CREATE TABLE IF NOT EXISTS backup_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      kind TEXT NOT NULL,
      path TEXT,
      created_at TEXT NOT NULL,
      clear_bytes INTEGER NOT NULL DEFAULT 0,
      manifest_json TEXT,
      status TEXT NOT NULL DEFAULT 'written'
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_backup_log_created '
        'ON backup_log (created_at DESC)');

    await db.execute('''CREATE TABLE IF NOT EXISTS incoming_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      remote_id TEXT NOT NULL UNIQUE,
      trans_id TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      payer_masked TEXT NOT NULL DEFAULT '',
      received_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'unclaimed',
      claimed_at TEXT,
      claimed_by TEXT,
      updated_at TEXT NOT NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_incoming_payments_status '
        'ON incoming_payments (status, received_at DESC)');

    await db.execute('''CREATE TABLE IF NOT EXISTS incoming_payment_claims (
      remote_id TEXT PRIMARY KEY,
      sale_id INTEGER NOT NULL,
      sale_uuid TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      reason TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_incoming_payment_claims_status '
        'ON incoming_payment_claims (status, updated_at)');

    await db.execute('''CREATE TABLE IF NOT EXISTS discount_reasons (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_discount_reasons_name ON discount_reasons (name)');

    await db.execute('''CREATE TABLE IF NOT EXISTS label_print_jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      barcode TEXT NOT NULL,
      price_minor INTEGER NOT NULL,
      quantity INTEGER NOT NULL,
      printed_quantity INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending',
      paper_width INTEGER NOT NULL,
      error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_label_print_jobs_status ON label_print_jobs (status, updated_at DESC)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        order_number TEXT NOT NULL UNIQUE,
        supplier_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft',
        ordered_at TEXT,
        expected_at TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        staff_id INTEGER,
        staff_name TEXT NOT NULL,
        synced_to_backend INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_order_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        purchase_order_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        qty REAL NOT NULL,
        unit_cost_minor INTEGER NOT NULL DEFAULT 0,
        received_qty REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    const discountReasons = <String>[
      'Staff discount',
      'Loyalty',
      'Damaged packaging',
      'Promotion',
      'Other',
    ];
    for (final name in discountReasons) {
      await db.insert(
        'discount_reasons',
        {'name': name},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Appends one normalized financial event within [txn], which is already part
  /// of a larger transaction. Never opens its own transaction.
  ///
  /// Mirrors the historical `DatabaseHelper._appendFinancialEvent`. The UUID
  /// minting and canonical hashing helpers intentionally remain on
  /// `DatabaseHelper` until every domain method is extracted.
  Future<int> appendFinancialEventInTransaction({
    required DatabaseExecutor txn,
    required String eventType,
    required String sourceType,
    int? sourceId,
    required String occurredAtUtc,
    int revenueMinor = 0,
    int cashInMinor = 0,
    int cashOutMinor = 0,
    int cogsMinor = 0,
    int operatingExpenseMinor = 0,
    int taxCollectedMinor = 0,
    int receivableDeltaMinor = 0,
    int payableDeltaMinor = 0,
    int customerDepositDeltaMinor = 0,
    int inventoryDeltaMilliunits = 0,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    FinancialEventContract.validate(
      eventType: eventType,
      sourceType: sourceType,
      sourceId: sourceId,
      occurredAtUtc: occurredAtUtc,
      revenueMinor: revenueMinor,
      cashInMinor: cashInMinor,
      cashOutMinor: cashOutMinor,
      cogsMinor: cogsMinor,
      operatingExpenseMinor: operatingExpenseMinor,
      taxCollectedMinor: taxCollectedMinor,
      receivableDeltaMinor: receivableDeltaMinor,
      payableDeltaMinor: payableDeltaMinor,
      customerDepositDeltaMinor: customerDepositDeltaMinor,
      inventoryDeltaMilliunits: inventoryDeltaMilliunits,
    );
    final previousRows = await txn.query(
      'financial_events',
      columns: <String>['integrity_hash'],
      orderBy: 'id DESC',
      limit: 1,
    );
    final previousHash = previousRows.isEmpty
        ? null
        : previousRows.first['integrity_hash'] as String;
    final uuid = DatabaseHelper.newUuid();
    final metadataJson = jsonEncode(metadata);
    final canonical = DatabaseHelper.instance.financialEventCanonical(
      uuid: uuid,
      eventType: eventType,
      sourceType: sourceType,
      sourceId: sourceId,
      occurredAtUtc: occurredAtUtc,
      revenueMinor: revenueMinor,
      cashInMinor: cashInMinor,
      cashOutMinor: cashOutMinor,
      cogsMinor: cogsMinor,
      operatingExpenseMinor: operatingExpenseMinor,
      taxCollectedMinor: taxCollectedMinor,
      receivableDeltaMinor: receivableDeltaMinor,
      payableDeltaMinor: payableDeltaMinor,
      customerDepositDeltaMinor: customerDepositDeltaMinor,
      inventoryDeltaMilliunits: inventoryDeltaMilliunits,
      metadataJson: metadataJson,
      previousHash: previousHash,
    );
    final integrityHash =
        sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
    return txn.insert('financial_events', {
      ...canonical,
      'integrity_hash': integrityHash,
    });
  }

  /// Allocates cost from a pool to a sale within [txn]. Never opens its own
  /// transaction.
  Future<int> allocateCostPoolToSaleInTransaction({
    required DatabaseExecutor txn,
    required int poolId,
    required int saleId,
    required Money amount,
  }) async {
    if (amount.minorUnits <= 0) {
      throw StateError('A pool allocation must be more than zero');
    }
    final pools = await txn.query('cost_pools',
        where: 'id = ?', whereArgs: [poolId], limit: 1);
    if (pools.isEmpty) throw StateError('Cost pool not found');
    final pool = pools.first;
    final invested = (pool['invested_minor'] as num).toInt();
    final recovered = (pool['recovered_minor'] as num).toInt();
    if (recovered + amount.minorUnits > invested) {
      throw StateError('That allocation exceeds the pool remaining cost');
    }
    final sale = await txn.query('sales',
        columns: <String>['id'],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1);
    if (sale.isEmpty) throw StateError('Sale not found');
    final now = DateTime.now().toIso8601String();
    final allocationId = await txn.insert('sale_pool_allocations', {
      'pool_id': poolId,
      'sale_id': saleId,
      'amount_minor': amount.minorUnits,
      'created_at': now,
    });
    await txn.rawUpdate(
      'UPDATE cost_pools SET recovered_minor = recovered_minor + ? WHERE id = ?',
      [amount.minorUnits, poolId],
    );
    await appendFinancialEventInTransaction(
      txn: txn,
      eventType: 'cost_pool_allocation',
      sourceType: 'sale_pool_allocation',
      sourceId: allocationId,
      occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
      cogsMinor: amount.minorUnits,
      metadata: <String, Object?>{
        'pool_id': poolId,
        'sale_id': saleId,
      },
    );
    return allocationId;
  }

  // ── Public methods ─────────────────────────────────────────────────

  Future<int> recordExpense({
    required String uuid,
    required int categoryId,
    required Money amount,
    required String paidFrom,
    required String staffName,
    int? staffId,
    String? note,
    String? photoPath,
    int? approvedBy,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction<int>((txn) => recordExpenseInTransaction(
      txn,
      uuid: uuid,
      categoryId: categoryId,
      amount: amount,
      paidFrom: paidFrom,
      staffName: staffName,
      staffId: staffId,
      note: note,
      photoPath: photoPath,
      approvedBy: approvedBy,
    ));
  }

  /// Records an expense within [txn]. Never opens its own transaction.
  Future<int> recordExpenseInTransaction(Transaction txn, {
    required String uuid,
    required int categoryId,
    required Money amount,
    required String paidFrom,
    required String staffName,
    int? staffId,
    String? note,
    String? photoPath,
    int? approvedBy,
  }) async {
    if (uuid.trim().isEmpty) throw ArgumentError.value(uuid, 'uuid');
    if (amount.minorUnits <= 0) {
      throw StateError('An expense must be more than zero');
    }
    if (paidFrom != 'till_cash' &&
        paidFrom != 'other' &&
        paidFrom != 'payable') {
      throw StateError('An expense is paid from till cash, elsewhere or later');
    }
    final category = await txn.query('expense_categories',
        where: 'id = ? AND active = 1', whereArgs: [categoryId], limit: 1);
    if (category.isEmpty) throw StateError('Expense category not found');

    int? shiftId;
    if (paidFrom == 'till_cash') {
      final shifts = await txn.query('shifts',
          where: 'status = ?',
          whereArgs: ['open'],
          orderBy: 'start_time DESC',
          limit: 1);
      if (shifts.isEmpty) {
        throw StateError('Open a shift before paying from till cash');
      }
      shiftId = shifts.first['id'] as int;
    }
    final now = DateTime.now().toIso8601String();
    final eventAtUtc = DateTime.now().toUtc().toIso8601String();
    final expenseId = await txn.insert('expenses', {
      'uuid': uuid,
      'shift_id': shiftId,
      'category_id': categoryId,
      'amount_minor': amount.minorUnits,
      'paid_from': paidFrom,
      'note': note,
      'photo_path': photoPath,
      'staff_id': staffId,
      'approved_by': approvedBy,
      'staff_name': staffName,
      'created_at': now,
    });
    await appendFinancialEventInTransaction(
      txn: txn,
      eventType: 'expense',
      sourceType: 'expense',
      sourceId: expenseId,
      occurredAtUtc: eventAtUtc,
      cashOutMinor: paidFrom == 'till_cash' ? amount.minorUnits : 0,
      operatingExpenseMinor: amount.minorUnits,
      payableDeltaMinor: paidFrom == 'payable' ? amount.minorUnits : 0,
      metadata: <String, Object?>{
        'paid_from': paidFrom,
        'category_id': categoryId,
      },
    );
    return expenseId;
  }

  Future<int> recordExpensePayment({
    required String uuid,
    required int expenseId,
    required Money amount,
    required String paymentMethod,
    String? reference,
    int? shiftId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction<int>((txn) => recordExpensePaymentInTransaction(
      txn,
      uuid: uuid,
      expenseId: expenseId,
      amount: amount,
      paymentMethod: paymentMethod,
      reference: reference,
      shiftId: shiftId,
    ));
  }

  /// Pays an expense within [txn]. Never opens its own transaction.
  Future<int> recordExpensePaymentInTransaction(Transaction txn, {
    required String uuid,
    required int expenseId,
    required Money amount,
    required String paymentMethod,
    String? reference,
    int? shiftId,
  }) async {
    if (uuid.trim().isEmpty) throw ArgumentError.value(uuid, 'uuid');
    if (amount.minorUnits <= 0) {
      throw StateError('An expense payment must be more than zero');
    }
    if (!<String>{'cash', 'mpesa', 'bank_transfer'}.contains(paymentMethod)) {
      throw StateError('Unsupported expense payment method');
    }
    final expenses = await txn.query(
      'expenses',
      columns: <String>['amount_minor', 'paid_from', 'status'],
      where: 'id = ?',
      whereArgs: [expenseId],
      limit: 1,
    );
    if (expenses.isEmpty || expenses.first['status'] != 'posted') {
      throw StateError('Expense not found or already voided');
    }
    if (expenses.first['paid_from'] != 'payable') {
      throw StateError('Only unpaid expenses can receive a payment');
    }
    final paidRows = await txn.rawQuery(
      'SELECT COALESCE(SUM(amount_minor), 0) AS total '
      'FROM expense_payments WHERE expense_id = ?',
      [expenseId],
    );
    final paid = (paidRows.first['total'] as num?)?.toInt() ?? 0;
    final expenseAmount = (expenses.first['amount_minor'] as num).toInt();
    if (paid + amount.minorUnits > expenseAmount) {
      throw StateError('That payment exceeds the expense payable');
    }

    int? resolvedShiftId = shiftId;
    if (paymentMethod == 'cash') {
      if (resolvedShiftId == null) {
        final shifts = await txn.query(
          'shifts',
          where: 'status = ?',
          whereArgs: ['open'],
          orderBy: 'start_time DESC',
          limit: 1,
        );
        if (shifts.isEmpty) {
          throw StateError('Open a shift before paying cash');
        }
        resolvedShiftId = shifts.first['id'] as int;
      } else {
        final shifts = await txn.query(
          'shifts',
          where: 'id = ? AND status = ?',
          whereArgs: [resolvedShiftId, 'open'],
        );
        if (shifts.isEmpty) throw StateError('Shift is not open');
      }
    }

    final now = DateTime.now().toIso8601String();
    final paymentId = await txn.insert('expense_payments', {
      'uuid': uuid,
      'expense_id': expenseId,
      'amount_minor': amount.minorUnits,
      'payment_method': paymentMethod,
      'reference': reference,
      'shift_id': resolvedShiftId,
      'created_at': now,
    });
    await appendFinancialEventInTransaction(
      txn: txn,
      eventType: 'expense_payment',
      sourceType: 'expense_payment',
      sourceId: paymentId,
      occurredAtUtc: DateTime.parse(now).toUtc().toIso8601String(),
      cashOutMinor: amount.minorUnits,
      payableDeltaMinor: -amount.minorUnits,
      metadata: <String, Object?>{
        'expense_id': expenseId,
        'payment_method': paymentMethod,
        'shift_id': resolvedShiftId,
      },
    );
    return paymentId;
  }

  Future<void> voidExpense(int expenseId) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) => voidExpenseInTransaction(txn, expenseId));
  }

  /// Voids an expense within [txn]. Never opens its own transaction.
  Future<void> voidExpenseInTransaction(Transaction txn, int expenseId) async {
    final rows = await txn.query('expenses',
        columns: ['shift_id', 'status', 'amount_minor', 'paid_from'],
        where: 'id = ?',
        whereArgs: [expenseId],
        limit: 1);
    if (rows.isEmpty) throw StateError('Expense not found');
    if (rows.first['status'] != 'posted') {
      throw StateError('Expense is already voided');
    }
    if (rows.first['paid_from'] == 'payable') {
      final payments = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM expense_payments WHERE expense_id = ?',
        [expenseId],
      );
      if ((payments.first['count'] as num).toInt() > 0) {
        throw StateError('A paid payable expense cannot be voided');
      }
    }
    final shiftId = rows.first['shift_id'] as int?;
    if (shiftId != null) {
      final shifts = await txn.query('shifts',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [shiftId],
          limit: 1);
      if (shifts.isNotEmpty && shifts.first['status'] != 'open') {
        throw StateError('A closed shift cannot be changed');
      }
    }
    await txn.update('expenses', {'status': 'voided'},
        where: 'id = ?', whereArgs: [expenseId]);
    final amountMinor = (rows.first['amount_minor'] as num).toInt();
    final paidFrom = rows.first['paid_from'] as String;
    await appendFinancialEventInTransaction(
      txn: txn,
      eventType: 'expense_void',
      sourceType: 'expense',
      sourceId: expenseId,
      occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
      cashInMinor: paidFrom == 'till_cash' ? amountMinor : 0,
      operatingExpenseMinor: -amountMinor,
      payableDeltaMinor: paidFrom == 'payable' ? -amountMinor : 0,
      metadata: <String, Object?>{'paid_from': paidFrom},
    );
  }

  /// Creates a cost pool within [txn]. Never opens its own transaction.
  Future<int> createCostPoolInTransaction(Transaction txn, {
    required String uuid,
    required String name,
    required String poolType,
    String? note,
    Money? initialCost,
    Money? totalCost,
    Money? cost,
    Money? costAmount,
    String paidFrom = 'other',
    String entryType = 'purchase',
    String? description,
  }) async {
    if (uuid.trim().isEmpty || name.trim().isEmpty) {
      throw StateError('A cost pool needs an id and a name');
    }
    if (poolType != 'lot' && poolType != 'rolling_stock' && poolType != 'bale') {
      throw StateError('A cost pool is a lot, rolling stock or bale');
    }
    final resolvedCost = initialCost ?? totalCost ?? cost ?? costAmount;
    final poolId = await txn.insert('cost_pools', {
      'uuid': uuid,
      'name': name.trim(),
      'pool_type': poolType,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
    if (resolvedCost != null && resolvedCost.minorUnits > 0) {
      await addCostPoolEntryInTransaction(
        txn,
        uuid: '$uuid-entry',
        poolId: poolId,
        entryType: entryType,
        amount: resolvedCost,
        paidFrom: paidFrom,
        description: description ?? note,
      );
    }
    return poolId;
  }

  /// Creates a cost pool, opening its own transaction.
  Future<int> createCostPool({
    required String uuid,
    required String name,
    required String poolType,
    String? note,
    Money? initialCost,
    Money? totalCost,
    Money? cost,
    Money? costAmount,
    String paidFrom = 'other',
    String entryType = 'purchase',
    String? description,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction<int>((txn) => createCostPoolInTransaction(
      txn,
      uuid: uuid,
      name: name,
      poolType: poolType,
      note: note,
      initialCost: initialCost,
      totalCost: totalCost,
      cost: cost,
      costAmount: costAmount,
      paidFrom: paidFrom,
      entryType: entryType,
      description: description,
    ));
  }

  /// Adds a cost pool entry within [txn]. Never opens its own transaction.
  Future<int> addCostPoolEntryInTransaction(Transaction txn, {
    required String uuid,
    required int poolId,
    required String entryType,
    required Money amount,
    String paidFrom = 'other',
    String? description,
  }) async {
    const entryTypes = <String>{
      'purchase',
      'transport',
      'packaging',
      'sorting',
      'other',
    };
    if (!entryTypes.contains(entryType)) {
      throw StateError('Unknown cost-pool entry');
    }
    if (paidFrom != 'till_cash' &&
        paidFrom != 'other' &&
        paidFrom != 'credit') {
      throw StateError('A pool cost is paid from cash, elsewhere or credit');
    }
    if (amount.minorUnits <= 0) {
      throw StateError('A cost-pool entry must be more than zero');
    }
    final pools = await txn.query('cost_pools',
        where: "id = ? AND status = 'open'", whereArgs: [poolId], limit: 1);
    if (pools.isEmpty) throw StateError('Cost pool not found or closed');
    final now = DateTime.now().toIso8601String();
    final entryId = await txn.insert('cost_pool_entries', {
      'uuid': uuid,
      'pool_id': poolId,
      'entry_type': entryType,
      'amount_minor': amount.minorUnits,
      'paid_from': paidFrom,
      'description': description,
      'created_at': now,
    });
    await txn.rawUpdate(
      'UPDATE cost_pools SET invested_minor = invested_minor + ? WHERE id = ?',
      [amount.minorUnits, poolId],
    );
    await appendFinancialEventInTransaction(
      txn: txn,
      eventType: 'cost_pool_entry',
      sourceType: 'cost_pool_entry',
      sourceId: entryId,
      occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
      cashOutMinor: paidFrom == 'till_cash' ? amount.minorUnits : 0,
      payableDeltaMinor: paidFrom == 'credit' ? amount.minorUnits : 0,
      metadata: <String, Object?>{
        'pool_id': poolId,
        'entry_type': entryType,
        'paid_from': paidFrom,
      },
    );
    return entryId;
  }

  /// Adds a cost pool entry, opening its own transaction.
  Future<int> addCostPoolEntry({
    required String uuid,
    required int poolId,
    required String entryType,
    required Money amount,
    String paidFrom = 'other',
    String? description,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction<int>((txn) => addCostPoolEntryInTransaction(
      txn,
      uuid: uuid,
      poolId: poolId,
      entryType: entryType,
      amount: amount,
      paidFrom: paidFrom,
      description: description,
    ));
  }

  Future<List<Map<String, dynamic>>> getCostPools() async =>
      (await DatabaseHelper.instance.database)
          .query('cost_pools', orderBy: 'created_at DESC, id DESC');

  Future<List<Map<String, dynamic>>> getCostPoolEntries(int poolId) async =>
      (await DatabaseHelper.instance.database).query('cost_pool_entries',
          where: 'pool_id = ?',
          whereArgs: [poolId],
          orderBy: 'created_at DESC, id DESC');

  Future<List<Map<String, dynamic>>> getExpenses({int? shiftId}) async {
    final db = await DatabaseHelper.instance.database;
    if (shiftId != null) {
      return db.query('expenses',
          where: 'shift_id = ?', whereArgs: [shiftId],
          orderBy: 'created_at DESC');
    }
    return db.query('expenses', orderBy: 'created_at DESC');
  }

  /// Records a till movement within [txn]. Never opens its own transaction.
  Future<int> recordTillMovementInTransaction(Transaction txn, {
    required String uuid,
    required int shiftId,
    required String movementType,
    required Money amount,
    required String staffName,
    int? staffId,
    String? note,
  }) async {
    if (uuid.trim().isEmpty) throw ArgumentError.value(uuid, 'uuid');
    if (!<String>{'cash_in', 'cash_drop', 'float_adjustment'}
        .contains(movementType)) {
      throw StateError('Unknown till movement');
    }
    if (amount.minorUnits == 0) {
      throw StateError('A till movement must be more than zero');
    }
    final shifts = await txn.query('shifts',
        where: 'id = ? AND status = ?', whereArgs: [shiftId, 'open']);
    if (shifts.isEmpty) throw StateError('Shift is not open');
    final now = DateTime.now().toIso8601String();
    final movementId = await txn.insert('till_movements', {
      'uuid': uuid,
      'shift_id': shiftId,
      'movement_type': movementType,
      'amount_minor': amount.minorUnits,
      'note': note,
      'staff_id': staffId,
      'staff_name': staffName,
      'created_at': now,
    });
    await appendFinancialEventInTransaction(
      txn: txn,
      eventType: 'till_movement',
      sourceType: 'till_movement',
      sourceId: movementId,
      occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
      cashInMinor: amount.minorUnits > 0 ? amount.minorUnits : 0,
      cashOutMinor: amount.minorUnits < 0 ? -amount.minorUnits : 0,
      metadata: <String, Object?>{'movement_type': movementType},
    );
    return movementId;
  }

  /// Records a till movement, opening its own transaction.
  Future<int> recordTillMovement({
    required String uuid,
    required int shiftId,
    required String movementType,
    required Money amount,
    required String staffName,
    int? staffId,
    String? note,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction<int>((txn) => recordTillMovementInTransaction(
      txn,
      uuid: uuid,
      shiftId: shiftId,
      movementType: movementType,
      amount: amount,
      staffName: staffName,
      staffId: staffId,
      note: note,
    ));
  }

  /// Posts a stock receipt within [txn]. Never opens its own transaction.
  Future<int> postStockReceiptInTransaction(Transaction txn, {
    required List<StockReceiptLine> lines,
    int? supplierId,
    String? supplierRef,
    String? supplierPin,
    String? etimsInvoiceRef,
    int? inputVatMinor,
    String taxEvidenceStatus = 'needs_review',
    String? note,
    required String staffName,
    int? staffId,
    DateTime? receivedAt,
    String costingMode = 'weighted_average',
    int? purchaseOrderId,
  }) async {
    if (costingMode != 'weighted_average' && costingMode != 'last_cost') {
      throw ArgumentError.value(
          costingMode, 'costingMode', 'must be weighted_average or last_cost');
    }
    if (lines.isEmpty) {
      throw StateError('A delivery must contain at least one line');
    }
    final String now = (receivedAt ?? DateTime.now()).toIso8601String();
    int totalCost = 0;
    final List<({StockReceiptLine line, int oldCost, int newCost})> costs =
        <({StockReceiptLine line, int oldCost, int newCost})>[];

    final poLines = purchaseOrderId == null
        ? const <Map<String, Object?>>[]
        : await txn.query('purchase_order_lines',
            where: 'purchase_order_id = ?', whereArgs: [purchaseOrderId]);
    if (purchaseOrderId != null && poLines.isEmpty) {
      throw StateError('Purchase order not found');
    }

    for (final StockReceiptLine line in lines) {
      if (line.qty <= 0) {
        throw StateError('A received quantity must be more than zero');
      }
      final List<Map<String, Object?>> product = await txn.query(
        'products',
        columns: <String>[
          'id',
          'cost_price',
          'stock_qty',
          'track_variants',
          'track_expiry',
        ],
        where: 'id = ?',
        whereArgs: [line.productId],
        limit: 1,
      );
      if (product.isEmpty) {
        throw StateError('That product is not in the catalogue');
      }
      final tracksExpiry =
          (product.first['track_expiry'] as num?)?.toInt() == 1;
      if (tracksExpiry && line.expiryDate == null) {
        throw StateError(
            'An expiry date is required for ${line.productName}');
      }
      if (tracksExpiry &&
          !line.expiryDate!.isAfter(receivedAt ?? DateTime.now())) {
        throw StateError('The expiry date must be after the received date');
      }
      if (purchaseOrderId != null) {
        final matches = poLines.where(
            (row) => (row['product_id'] as num).toInt() == line.productId);
        if (matches.isEmpty) {
          throw StateError('Product is not on the purchase order');
        }
        final poLine = matches.first;
        final ordered = (poLine['qty'] as num).toDouble();
        final received = (poLine['received_qty'] as num?)?.toDouble() ?? 0;
        if (received + line.qty > ordered + DatabaseHelper.qtyEpsilon) {
          throw StateError('Received quantity exceeds the purchase order');
        }
      }
      final int oldCost = (product.first['cost_price'] as num?)?.toInt() ?? 0;
      final int newCost;
      if (costingMode == 'weighted_average') {
        newCost = DatabaseHelper.weightedAverageCost(
          onHandMinor: oldCost,
          onHandQty: (product.first['stock_qty'] as num?)?.toDouble() ?? 0,
          incomingQty: line.qty,
          incomingMinor: line.unitCost.minorUnits,
        );
      } else {
        newCost = line.unitCost.minorUnits;
      }
      final int lineCost = (line.unitCost.minorUnits * line.qty).round();
      totalCost += lineCost;
      costs.add((line: line, oldCost: oldCost, newCost: newCost));

      final double balance =
          await DatabaseHelper.instance.productBalanceAfter(txn, line.productId);
      await DatabaseHelper.instance.writeStockMovement(
        txn: txn,
        productId: line.productId,
        variantId: line.variantId,
        type: StockMovementType.receipt,
        qtyDelta: line.qty,
        unitCostMinor: newCost,
        referenceType: 'stock_receipt',
        referenceId: null,
        staffId: staffId,
        staffName: staffName,
        note: 'Received',
        balanceAfter: balance,
        createdAt: now,
      );
      await CustomerRepository.instance.restoreStockCount(
        txn,
        productId: line.productId,
        variantId: line.variantId,
        units: line.qty,
      );
    }

    final int receiptId = await txn.insert('stock_receipts', {
      'supplier_id': supplierId,
      'supplier_ref': supplierRef,
      'supplier_pin': supplierPin,
      'etims_invoice_ref': etimsInvoiceRef,
      'input_vat_minor': inputVatMinor,
      'tax_evidence_status': taxEvidenceStatus,
      'received_at': now,
      'staff_id': staffId,
      'staff_name': staffName,
      'total_cost_minor': totalCost,
      'status': 'posted',
      'note': note,
      'synced_to_backend': 0,
    });

    for (final ({StockReceiptLine line, int oldCost, int newCost}) cost
        in costs) {
      await txn.insert('stock_receipt_items', {
        'receipt_id': receiptId,
        'product_id': cost.line.productId,
        'variant_id': cost.line.variantId,
        'product_name': cost.line.productName,
        'qty': cost.line.qty,
        'unit_cost_minor': cost.line.unitCost.minorUnits,
        'line_cost_minor':
            (cost.line.unitCost.minorUnits * cost.line.qty).round(),
        'old_cost_minor': cost.oldCost,
        'new_cost_minor': cost.newCost,
        'expiry_date': cost.line.expiryDate?.toIso8601String(),
        'batch_code': cost.line.batchCode,
      });
      if (cost.line.expiryDate != null) {
        final expiry = cost.line.expiryDate!;
        final endOfDay =
            DateTime(expiry.year, expiry.month, expiry.day, 23, 59, 59, 999);
        await txn.insert('stock_batches', {
          'uuid': DatabaseHelper.newUuid(),
          'product_id': cost.line.productId,
          'variant_id': cost.line.variantId,
          'batch_code': cost.line.batchCode,
          'receipt_id': receiptId,
          'received_at': now,
          'expires_at': endOfDay.toIso8601String(),
          'qty_remaining': cost.line.qty,
          'unit_cost_minor': cost.line.unitCost.minorUnits,
          'status': 'active',
        });
      }
      await txn.insert('product_cost_history', {
        'product_id': cost.line.productId,
        'variant_id': cost.line.variantId,
        'effective_at': now,
        'old_cost_minor': cost.oldCost,
        'new_cost_minor': cost.newCost,
        'reason': 'receipt',
        'receipt_id': receiptId,
      });
      await txn.rawUpdate(
        'UPDATE products SET cost_price = ?, updated_at = ? WHERE id = ?',
        <Object?>[cost.newCost, now, cost.line.productId],
      );
    }

    if (purchaseOrderId != null) {
      for (final line in lines) {
        await txn.rawUpdate(
          'UPDATE purchase_order_lines SET received_qty = received_qty + ? '
          'WHERE purchase_order_id = ? AND product_id = ?',
          [line.qty, purchaseOrderId, line.productId],
        );
      }
      final remaining = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM purchase_order_lines '
        'WHERE purchase_order_id = ? AND received_qty < qty',
        [purchaseOrderId],
      );
      await txn.update(
        'purchase_orders',
        {
          'status': ((remaining.first['c'] as num?)?.toInt() ?? 0) == 0
              ? 'received'
              : 'partial',
          'synced_to_backend': 0,
        },
        where: 'id = ?',
        whereArgs: [purchaseOrderId],
      );
    }

    await appendFinancialEventInTransaction(
      txn: txn,
      eventType: 'purchase',
      sourceType: 'stock_receipt',
      sourceId: receiptId,
      occurredAtUtc: DateTime.parse(now).toUtc().toIso8601String(),
      payableDeltaMinor: totalCost,
      inventoryDeltaMilliunits: lines.fold<int>(
        0,
        (sum, line) => sum + (line.qty * 1000).round(),
      ),
      metadata: <String, Object?>{
        'supplier_id': supplierId,
        'purchase_order_id': purchaseOrderId,
        'line_count': lines.length,
        'costing_mode': costingMode,
      },
    );

    return receiptId;
  }

  /// Posts a stock receipt, opening its own transaction.
  Future<int> postStockReceipt({
    required List<StockReceiptLine> lines,
    int? supplierId,
    String? supplierRef,
    String? supplierPin,
    String? etimsInvoiceRef,
    int? inputVatMinor,
    String taxEvidenceStatus = 'needs_review',
    String? note,
    required String staffName,
    int? staffId,
    DateTime? receivedAt,
    String costingMode = 'weighted_average',
    int? purchaseOrderId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction<int>((txn) => postStockReceiptInTransaction(
      txn,
      lines: lines,
      supplierId: supplierId,
      supplierRef: supplierRef,
      supplierPin: supplierPin,
      etimsInvoiceRef: etimsInvoiceRef,
      inputVatMinor: inputVatMinor,
      taxEvidenceStatus: taxEvidenceStatus,
      note: note,
      staffName: staffName,
      staffId: staffId,
      receivedAt: receivedAt,
      costingMode: costingMode,
      purchaseOrderId: purchaseOrderId,
    ));
  }
}
