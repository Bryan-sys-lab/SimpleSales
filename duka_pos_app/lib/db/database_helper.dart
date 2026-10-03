import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/models.dart';

/// Single source of truth for local storage. Every screen reads/writes
/// through here rather than touching sqflite directly, so the schema only
/// lives in one place and checkout stays a single atomic transaction
/// (see recordSale) — a mid-sale crash or dead battery should never leave
/// stock decremented without a matching sale row, or vice versa.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();
  Database? _db;
  String _workspaceKey = 'legacy';

  /// Must run before the first database access. The legacy path is retained
  /// for existing installations; every additional shop gets a separate file.
  Future<void> initializeWorkspace(String workspaceKey) async {
    if (workspaceKey.trim().isEmpty) {
      throw ArgumentError.value(workspaceKey, 'workspaceKey');
    }
    if (_db != null && _workspaceKey == workspaceKey) return;
    await _db?.close();
    _db = null;
    _workspaceKey = workspaceKey;
  }

  Future<void> switchWorkspace(String workspaceKey) =>
      initializeWorkspace(workspaceKey);

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  /// Test-only: Reset the singleton instance for test isolation
  @visibleForTesting
  static void resetForTests() {
    instance._db = null;
  }

  /// Bump this every time the schema changes, and add the matching branch in
  /// [_onUpgrade]. Never edit an already-released migration after it has
  /// shipped — always add a new one, even for a one-line fix — because a
  /// shop's phone may be several versions behind and needs every step run
  /// in order to land on the current schema without data loss.
  static const _schemaVersion = 10;

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final safeKey = _workspaceKey.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final path = _workspaceKey == 'legacy'
        ? join(dbPath, 'duka_pos.db')
        : join(dbPath, 'duka_pos_$safeKey.db');
    return openDatabase(path,
        version: _schemaVersion, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  /// Test-only: a fresh, isolated in-memory instance with the real schema,
  /// bypassing getDatabasesPath() (which needs a platform channel that
  /// doesn't exist in a plain `flutter test` run). Pair with
  /// sqflite_common_ffi's databaseFactoryFfi in test setUp — see
  /// test/database_helper_test.dart for the exact pattern.
  @visibleForTesting
  static Future<DatabaseHelper> openInMemoryForTests() async {
    // sqflite_common_ffi caches the literal ':memory:' handle in some
    // versions; a unique URI keeps each test isolated even when the previous
    // singleton connection has not finished closing.
    final uniqueMemoryPath =
        'file:duka_test_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=private';
    instance._db = await databaseFactory.openDatabase(
      uniqueMemoryPath,
      options: OpenDatabaseOptions(
          version: _schemaVersion, onCreate: instance._onCreate),
    );
    return instance;
  }

  /// v1 -> v2: adds remote_id, used only once the backend/M-Pesa integration
  /// is turned on (see services/backend_service.dart). Nullable and unused
  /// for shops that stay in pure offline/cash mode — this column costs them
  /// nothing. Next migration goes in its own `if (oldVersion < 3)` block
  /// below this one, never editing this block after it has shipped.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE products ADD COLUMN remote_id TEXT');
    }
    if (oldVersion < 3) {
      await db.execute(
          "ALTER TABLE sales ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash'");
      await db.execute('ALTER TABLE sales ADD COLUMN payment_reference TEXT');
    }
    if (oldVersion < 4) {
      await db.execute(
          "ALTER TABLE sales ADD COLUMN amount_tendered REAL NOT NULL DEFAULT 0");
      await db.execute(
          "ALTER TABLE sales ADD COLUMN change_given REAL NOT NULL DEFAULT 0");
      await db.execute(
          'UPDATE sales SET amount_tendered = total WHERE amount_tendered = 0');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE staff ADD COLUMN remote_id TEXT');
    }
    if (oldVersion < 6) {
      await db.execute('''CREATE TABLE staff_deletion_tombstones (
        staff_id INTEGER PRIMARY KEY,
        remote_id TEXT,
        deleted_at TEXT NOT NULL
      )''');
    }
    if (oldVersion < 7) {
      await db.execute(
          "ALTER TABLE staff ADD COLUMN role TEXT NOT NULL DEFAULT 'cashier'");
    }
    if (oldVersion < 8) {
      await db.execute(
          "ALTER TABLE products ADD COLUMN bottle_ml INTEGER NOT NULL DEFAULT 750");
      await db.execute('ALTER TABLE products ADD COLUMN half_price REAL');
      await db.execute('ALTER TABLE products ADD COLUMN quarter_price REAL');
      await db.execute(
          "ALTER TABLE sale_items ADD COLUMN portion TEXT NOT NULL DEFAULT 'full'");
      await db.execute(
          'ALTER TABLE sale_items ADD COLUMN portion_ml INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 9) {
      await db.execute(
          "ALTER TABLE owner ADD COLUMN email TEXT NOT NULL DEFAULT ''");
    }
    if (oldVersion < 10) {
      // Stable staff identity on the financial ledgers so historical rows are
      // never re-attributed by display name (see deleteStaffWithTombstone).
      await db.execute('ALTER TABLE sales ADD COLUMN staff_id INTEGER');
      await db
          .execute('ALTER TABLE stock_adjustments ADD COLUMN staff_id INTEGER');
      // Indexes declared in _onCreate must also exist for upgraded installs,
      // otherwise an upgraded till permanently full-scans these tables.
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sales_date ON sales (created_at)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items (product_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items (sale_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sales_staff ON sales (staff_id)');
      await db.execute('''CREATE TABLE IF NOT EXISTS pending_payments (
        reference TEXT PRIMARY KEY,
        phone_number TEXT,
        amount REAL NOT NULL,
        cart_json TEXT NOT NULL,
        staff_name TEXT,
        staff_id INTEGER,
        created_at TEXT NOT NULL
      )''');

      // Backfill the new stable ids onto pre-v10 history.
      //
      // Without this, every row written before the upgrade has staff_id NULL
      // and `deleteStaffWithTombstone` — which now matches on staff_id only —
      // silently stops anonymising the ledger it was written to protect. The
      // backfill is deliberately conservative: a name that maps to more than
      // one staff row is ambiguous (a removed cashier whose display name was
      // later reused) and is left NULL rather than guessed at, so no history
      // is ever re-attributed to the wrong person.
      await db.rawUpdate('''
        UPDATE sales
        SET staff_id = (
          SELECT MIN(s.id) FROM staff s
          WHERE s.name = sales.staff_name
            AND (SELECT COUNT(*) FROM staff t WHERE t.name = sales.staff_name) = 1
        )
        WHERE staff_id IS NULL
          AND staff_name IN (
            SELECT name FROM staff GROUP BY name HAVING COUNT(*) = 1
          )
      ''');
      await db.rawUpdate('''
        UPDATE stock_adjustments
        SET staff_id = (
          SELECT MIN(s.id) FROM staff s
          WHERE s.name = stock_adjustments.staff_name
            AND (SELECT COUNT(*) FROM staff t WHERE t.name = stock_adjustments.staff_name) = 1
        )
        WHERE staff_id IS NULL
          AND staff_name IN (
            SELECT name FROM staff GROUP BY name HAVING COUNT(*) = 1
          )
      ''');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE owner (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        name TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        email TEXT NOT NULL,
        shop_name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE staff (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        remote_id TEXT,
        role TEXT NOT NULL DEFAULT 'cashier'
      )
    ''');
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT,
        cost_price REAL NOT NULL,
        sell_price REAL NOT NULL,
        stock_qty REAL NOT NULL DEFAULT 0,
        reorder_level INTEGER NOT NULL DEFAULT 5,
        bottle_ml INTEGER NOT NULL DEFAULT 750,
        half_price REAL,
        quarter_price REAL,
        excise_stamp_batch TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT,
        remote_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staff_name TEXT NOT NULL,
        staff_id INTEGER,
        total REAL NOT NULL,
        profit REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        payment_reference TEXT,
        amount_tendered REAL NOT NULL DEFAULT 0,
        change_given REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        qty REAL NOT NULL,
        unit_price REAL NOT NULL,
        unit_cost REAL NOT NULL,
        portion TEXT NOT NULL DEFAULT 'full',
        portion_ml INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (sale_id) REFERENCES sales (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE stock_adjustments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        delta INTEGER NOT NULL,
        reason TEXT,
        staff_name TEXT NOT NULL,
        staff_id INTEGER,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_sales_date ON sales (created_at)');
    await db.execute(
        'CREATE INDEX idx_sale_items_product ON sale_items (product_id)');
    await db
        .execute('CREATE INDEX idx_sale_items_sale ON sale_items (sale_id)');
    await db.execute('CREATE INDEX idx_sales_staff ON sales (staff_id)');
    await db.execute('''CREATE TABLE staff_deletion_tombstones (
      staff_id INTEGER PRIMARY KEY,
      remote_id TEXT,
      deleted_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE pending_payments (
      reference TEXT PRIMARY KEY,
      phone_number TEXT,
      amount REAL NOT NULL,
      cart_json TEXT NOT NULL,
      staff_name TEXT,
      staff_id INTEGER,
      created_at TEXT NOT NULL
    )''');
  }

  // ---------------- Owner ----------------
  Future<Owner?> getOwner() async {
    final rows = await (await database).query('owner', where: 'id = 1');
    return rows.isEmpty ? null : Owner.fromMap(rows.first);
  }

  Future<void> createOwner(Owner owner) async {
    await (await database).insert('owner', owner.toMap());
  }

  Future<void> updateOwnerPin(String pinHash) async {
    await (await database)
        .update('owner', {'pin_hash': pinHash}, where: 'id = 1');
  }

  /// Re-derives a staff PIN hash in place (used when upgrading a legacy
  /// single-round SHA-256 hash to PBKDF2 on successful sign-in).
  Future<void> updateStaffPin(int id, String pinHash) async {
    await (await database).update('staff', {'pin_hash': pinHash},
        where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Staff ----------------
  Future<List<Staff>> getStaff({bool activeOnly = true}) async {
    final rows = await (await database).query('staff',
        where: activeOnly ? 'active = 1' : null, orderBy: 'name');
    return rows.map((r) => Staff.fromMap(r)).toList();
  }

  Future<int> addStaff(Staff staff) async {
    final values = staff.toMap()..remove('id');
    return (await database).insert('staff', values);
  }

  Future<void> setStaffRemoteId(int id, String remoteId) async {
    await (await database).update('staff', {'remote_id': remoteId},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> resetStaffPin(int id, String pinHash) async {
    await (await database).update('staff', {'pin_hash': pinHash},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deactivateStaff(int id) async {
    await (await database)
        .update('staff', {'active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteStaffWithTombstone(Staff staff) async {
    final db = await database;
    await db.transaction((txn) async {
      const deletedLabel = 'Deleted cashier';
      // Resolve the display name this cashier is being removed under *before*
      // the row is relabelled, so the legacy fallback below still has the
      // original name to match.
      final originalName = staff.name;
      await txn.update('staff', {'active': 0, 'name': deletedLabel},
          where: 'id = ?', whereArgs: [staff.id]);

      // Relabel historical rows by staff_id. Matching on staff_name alone would
      // also rewrite a *different* cashier's history whenever a removed
      // cashier's name is later reused, and would irreversibly destroy the
      // per-cashier attribution that shrinkage review depends on.
      //
      // The name fallback is guarded by `staff_id IS NULL` *and* by the name
      // being unique across the staff table, so it can only ever claim rows
      // that predate stable ids and unambiguously belong to this person. The
      // v10 migration backfills those rows, so this is a safety net for a till
      // that was already on v10 before that backfill shipped — not a path that
      // can reassign a row belonging to somebody else.
      for (final table in ['sales', 'stock_adjustments']) {
        await txn.rawUpdate(
            'UPDATE $table SET staff_name = ? WHERE staff_id = ?', [deletedLabel, staff.id]);
        if (originalName.isNotEmpty && originalName != deletedLabel) {
          final nameMatches = await txn.rawQuery(
              'SELECT COUNT(*) AS c FROM staff WHERE name = ?', [originalName]);
          if ((nameMatches.first['c'] as int? ?? 0) == 1) {
            await txn.rawUpdate(
                'UPDATE $table SET staff_name = ? WHERE staff_id IS NULL AND staff_name = ?',
                [deletedLabel, originalName]);
          }
        }
      }

      await txn.insert(
          'staff_deletion_tombstones',
          {
            'staff_id': staff.id,
            'remote_id': staff.remoteId,
            'deleted_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Map<String, dynamic>>> getStaffDeletionTombstones() async =>
      (await database).query('staff_deletion_tombstones');

  Future<void> clearStaffDeletionTombstone(int staffId) async {
    await (await database).delete('staff_deletion_tombstones',
        where: 'staff_id = ?', whereArgs: [staffId]);
  }

  // ---------------- Products ----------------
  Future<List<Product>> getProducts({bool activeOnly = true}) async {
    final rows = await (await database).query('products',
        where: activeOnly ? 'active = 1' : null, orderBy: 'name');
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  Future<int> upsertProduct(Product p) async {
    final db = await database;
    if (p.id == null) {
      return db.insert('products', p.toMap());
    } else {
      final values = p.toMap();
      // Older imports and editor forms may not carry the backend ID. Never
      // erase it during a local edit; remote linkage is durable metadata.
      if (p.remoteId == null) values.remove('remote_id');
      final updated = await db
          .update('products', values, where: 'id = ?', whereArgs: [p.id]);
      if (updated == 0) {
        // The row does not exist locally (typical when restoring an exported
        // workbook onto a fresh or reinstalled device). Fall back to an insert
        // so recovery works instead of aborting on the first product.
        values.remove('id');
        return db.insert('products', values);
      }
      return p.id!;
    }
  }

  /// Bulk upsert in a single transaction.
  ///
  /// Bulk import previously called [upsertProduct] per row, which meant one
  /// implicit transaction and one journal fsync per product. This makes an
  /// import all-or-nothing (a mid-file failure previously left half the
  /// catalogue applied) and fast.
  Future<void> upsertProducts(List<Product> products) async {
    if (products.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final p in products) {
        final values = p.toMap()..remove('id');
        if (p.id == null) {
          await txn.insert('products', values);
          continue;
        }
        if (p.remoteId == null) values.remove('remote_id');
        final updated = await txn
            .update('products', values, where: 'id = ?', whereArgs: [p.id]);
        if (updated == 0) {
          // Row not present locally (restore onto a fresh device): insert it.
          await txn.insert('products', values);
        }
      }
    });
  }

  /// Durable record of an M-Pesa push whose outcome is not yet confirmed.
  ///
  /// Written *before* polling. A timed-out push leaves the row behind so the
  /// cart is never silently dropped and the customer cannot be charged twice
  /// by pushing the same basket again; [resolvePendingPayment] clears it once
  /// the outcome is known.
  Future<void> recordPendingPayment({
    required String reference,
    required double amount,
    required String cartJson,
    String? phoneNumber,
    String? staffName,
    int? staffId,
  }) async {
    await (await database).insert(
        'pending_payments',
        {
          'reference': reference,
          'phone_number': phoneNumber,
          'amount': amount,
          'cart_json': cartJson,
          'staff_name': staffName,
          'staff_id': staffId,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> hasPendingPayment(String reference) async {
    final rows = await (await database).query('pending_payments',
        where: 'reference = ?', whereArgs: [reference], limit: 1);
    return rows.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getPendingPayments() async =>
      (await database).query('pending_payments', orderBy: 'created_at ASC');

  /// Pending rows old enough that the provider will never confirm them.
  ///
  /// Blocking checkout on *every* row forever would let one abandoned push
  /// disable M-Pesa at a till permanently, so checkout only blocks on rows
  /// inside [staleAfter]. Anything older is swept by
  /// [deleteStalePendingPayments] and reconciled from Reports instead.
  static const Duration pendingPaymentStaleAfter = Duration(hours: 24);

  static bool isPendingPaymentStale(Map<String, dynamic> row,
      {Duration staleAfter = pendingPaymentStaleAfter}) {
    final created = DateTime.tryParse(row['created_at'] as String? ?? '');
    if (created == null) return true;
    return DateTime.now().difference(created) >= staleAfter;
  }

  /// Outstanding rows that should still block a new STK push, oldest first.
  Future<List<Map<String, dynamic>>> getBlockingPendingPayments({
    Duration staleAfter = pendingPaymentStaleAfter,
  }) async {
    final rows = await getPendingPayments();
    return rows
        .where((row) => !isPendingPaymentStale(row, staleAfter: staleAfter))
        .toList();
  }

  /// Drops rows the provider will never confirm, so a single abandoned push
  /// cannot disable M-Pesa at this till permanently. Returns the references
  /// removed for reporting.
  Future<List<String>> deleteStalePendingPayments({
    Duration staleAfter = pendingPaymentStaleAfter,
  }) async {
    final rows = await getPendingPayments();
    final stale = rows
        .where((row) => isPendingPaymentStale(row, staleAfter: staleAfter))
        .toList();
    for (final row in stale) {
      await resolvePendingPayment(row['reference'] as String? ?? '');
    }
    return stale
        .map((row) => row['reference'] as String? ?? '')
        .where((reference) => reference.isNotEmpty)
        .toList();
  }

  Future<void> resolvePendingPayment(String reference) async {
    await (await database).delete('pending_payments',
        where: 'reference = ?', whereArgs: [reference]);
  }

  Future<void> setProductRemoteId(int id, String remoteId) async {
    await (await database).update('products', {'remote_id': remoteId},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Batch form of [setProductRemoteId], applied in a single transaction.
  Future<void> setProductRemoteIds(Map<int, String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final entry in ids.entries) {
        await txn.update('products', {'remote_id': entry.value},
            where: 'id = ?', whereArgs: [entry.key]);
      }
    });
  }

  Future<void> deactivateProduct(int id) async {
    await (await database)
        .update('products', {'active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> adjustStock(StockAdjustment adj, {int? staffId}) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('products',
          where: 'id = ?', whereArgs: [adj.productId], limit: 1);
      if (rows.isEmpty) throw StateError('Product not found');
      final currentStock = (rows.first['stock_qty'] as num).toDouble();
      if (currentStock + adj.delta < 0) {
        throw StateError('Stock cannot go below zero');
      }
      await txn.insert('stock_adjustments', {
        ...adj.toMap(),
        'staff_id': staffId,
      });
      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty + ?, updated_at = ? WHERE id = ?',
        [adj.delta, DateTime.now().toIso8601String(), adj.productId],
      );
    });
  }

  Future<List<StockAdjustment>> getRecentAdjustments({int limit = 30}) async {
    final rows = await (await database)
        .query('stock_adjustments', orderBy: 'created_at DESC', limit: limit);
    return rows.map((r) => StockAdjustment.fromMap(r)).toList();
  }

  // ---------------- Sales (atomic checkout) ----------------
  /// Writes the sale, its line items, and decrements stock for every item —
  /// all inside one transaction. If the app crashes or loses power mid-call,
  /// SQLite rolls the whole thing back rather than leaving a half-applied sale.
  /// [enforceStock] is true for the normal till checkout, where this is the
  /// only place stock gets checked and it's correct to refuse an oversell.
  /// Pass false only for a sale whose payment (and stock check) was already
  /// confirmed elsewhere — specifically an M-Pesa sale confirmed by the
  /// backend, which holds its own authoritative stock copy for that path
  /// (see services/backend_service.dart). In that case stock is clamped at
  /// zero rather than thrown on, since refusing to record a sale that a
  /// customer has already genuinely paid for would be worse than a local
  /// stock count briefly reading zero instead of a small negative — but a
  /// mismatch here is a real signal the two stock copies have drifted and
  /// is worth the owner's attention (see the backend README's sync caveat).
  Future<int> recordSale({
    required String staffName,
    required List<SaleItem> items,
    bool enforceStock = true,
    String paymentMethod = 'cash',
    String? paymentReference,
    double? amountTendered,
    int? staffId,
  }) async {
    if (items.isEmpty) {
      throw StateError('A sale must contain at least one item');
    }
    const allowedPaymentMethods = {
      'cash',
      'card',
      'bank_transfer',
      'mobile_money_manual',
      'mpesa'
    };
    if (!allowedPaymentMethods.contains(paymentMethod)) {
      throw StateError('Unsupported payment method');
    }
    if (items.any((item) => item.qty <= 0 || !item.qty.isFinite)) {
      throw StateError('Sale quantities must be positive');
    }
    // The cart is keyed on (product, portion), so a single bottle can appear as
    // several lines (e.g. one full + one half). Stock is therefore accumulated
    // per product before the availability check instead of rejecting repeats.
    double portionFactor(SaleItem item) => item.portion == 'half'
        ? 0.5
        : item.portion == 'quarter'
            ? 0.25
            : 1.0;
    final requiredUnits = <int, double>{};
    for (final item in items) {
      requiredUnits[item.productId] =
          (requiredUnits[item.productId] ?? 0) + item.qty * portionFactor(item);
    }
    final db = await database;
    final total = items.fold<double>(0, (a, it) => a + it.unitPrice * it.qty);
    final profit = items.fold<double>(
        0, (a, it) => a + (it.unitPrice - it.unitCost) * it.qty);
    final paid = amountTendered ?? total;
    if (!paid.isFinite || paid < total) {
      throw StateError('Amount received cannot be less than the sale total');
    }
    final change = paid - total;
    final now = DateTime.now().toIso8601String();

    return db.transaction<int>((txn) async {
      final stockByProduct = <int, double>{};
      for (final entry in requiredUnits.entries) {
        final current = await txn.query('products',
            where: 'id = ?', whereArgs: [entry.key], limit: 1);
        if (current.isEmpty) {
          final missing = items.firstWhere((it) => it.productId == entry.key);
          throw StateError('Product not found: ${missing.productName}');
        }
        final available = (current.first['stock_qty'] as num).toDouble();
        stockByProduct[entry.key] = available;
        if (enforceStock && available < entry.value) {
          final offending = items.firstWhere((it) => it.productId == entry.key);
          throw StateError('Not enough stock for ${offending.productName}');
        }
      }
      final saleId = await txn.insert('sales', {
        'staff_name': staffName,
        'staff_id': staffId,
        'total': total,
        'profit': profit,
        'payment_method': paymentMethod,
        'payment_reference': paymentReference,
        'amount_tendered': paid,
        'change_given': change,
        'created_at': now,
      });
      for (final it in items) {
        final fraction = portionFactor(it);
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': it.productId,
          'product_name': it.productName,
          'qty': it.qty,
          'unit_price': it.unitPrice,
          'unit_cost': it.unitCost,
          'portion': it.portion,
          'portion_ml': it.portionMl,
        });
        await txn.rawUpdate(
          'UPDATE products SET stock_qty = MAX(0, stock_qty - ?), updated_at = ? WHERE id = ?',
          [it.qty * fraction, now, it.productId],
        );
      }
      return saleId;
    });
  }

  /// Sales, newest first.
  ///
  /// [since] is inclusive and [after] is exclusive. Incremental exports use
  /// [after] so a sale on the boundary is appended exactly once rather than
  /// duplicated on every sync; one-shot range exports use [since].
  Future<List<Sale>> getSales({
    DateTime? since,
    DateTime? after,
    String? staffName,
    int? limit,
    bool withItems = true,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];
    if (after != null) {
      where.add('created_at > ?');
      args.add(after.toIso8601String());
    } else if (since != null) {
      where.add('created_at >= ?');
      args.add(since.toIso8601String());
    }
    if (staffName != null) {
      where.add('staff_name = ?');
      args.add(staffName);
    }
    final rows = await db.query(
      'sales',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    if (rows.isEmpty) return [];
    // Callers that only need per-sale aggregates (dashboard, reports) skip the
    // line-item query entirely; otherwise this hydrates every line item ever
    // recorded on every dashboard load.
    Map<dynamic, List<Map<String, dynamic>>> itemsBySale =
        <dynamic, List<Map<String, dynamic>>>{};
    if (withItems) {
      final saleIds = rows.map((row) => row['id']).toList();
      final itemRows = await db.query(
        'sale_items',
        where: 'sale_id IN (${List.filled(saleIds.length, '?').join(',')})',
        whereArgs: saleIds,
      );
      for (final item in itemRows) {
        (itemsBySale[item['sale_id']] ??= []).add(item);
      }
    }
    final sales = <Sale>[];
    for (final r in rows) {
      sales.add(Sale.fromMap(r).let((s) => Sale(
            id: s.id,
            staffName: s.staffName,
            total: s.total,
            profit: s.profit,
            createdAt: s.createdAt,
            paymentMethod: s.paymentMethod,
            paymentReference: s.paymentReference,
            amountTendered: s.amountTendered,
            changeGiven: s.changeGiven,
            items: (itemsBySale[r['id']] ?? const <Map<String, dynamic>>[])
                .map(SaleItem.fromMap)
                .toList(),
          )));
    }
    return sales;
  }
}

/// Small Kotlin-style `let` helper so we can transform the just-parsed Sale
/// inline above without an intermediate mutable variable.
extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
