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
  static const _schemaVersion = 9;

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
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_sales_date ON sales (created_at)');
    await db.execute(
        'CREATE INDEX idx_sale_items_product ON sale_items (product_id)');
    await db.execute('''CREATE TABLE staff_deletion_tombstones (
      staff_id INTEGER PRIMARY KEY,
      remote_id TEXT,
      deleted_at TEXT NOT NULL
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
      await txn.update('staff', {'active': 0, 'name': deletedLabel},
          where: 'id = ?', whereArgs: [staff.id]);
      await txn.update('sales', {'staff_name': deletedLabel},
          where: 'staff_name = ?', whereArgs: [staff.name]);
      await txn.update('stock_adjustments', {'staff_name': deletedLabel},
          where: 'staff_name = ?', whereArgs: [staff.name]);
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
      if (updated == 0) throw StateError('Product not found');
      return p.id!;
    }
  }

  Future<void> setProductRemoteId(int id, String remoteId) async {
    await (await database).update('products', {'remote_id': remoteId},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deactivateProduct(int id) async {
    await (await database)
        .update('products', {'active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> adjustStock(StockAdjustment adj) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('products',
          where: 'id = ?', whereArgs: [adj.productId], limit: 1);
      if (rows.isEmpty) throw StateError('Product not found');
      final currentStock = (rows.first['stock_qty'] as num).toDouble();
      if (currentStock + adj.delta < 0) {
        throw StateError('Stock cannot go below zero');
      }
      await txn.insert('stock_adjustments', adj.toMap());
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
    final productIds = items.map((item) => item.productId).toSet();
    if (productIds.length != items.length) {
      throw StateError('A product can only appear once in a sale');
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
      final products = <int, double>{};
      for (final it in items) {
        final current = await txn.query('products',
            where: 'id = ?', whereArgs: [it.productId], limit: 1);
        if (current.isEmpty) {
          throw StateError('Product not found: ${it.productName}');
        }
        products[it.productId] = (current.first['stock_qty'] as num).toDouble();
        final fraction = it.portion == 'half'
            ? 0.5
            : it.portion == 'quarter'
                ? 0.25
                : 1.0;
        final stockUnits = it.qty * fraction;
        if (enforceStock && products[it.productId]! < stockUnits) {
          throw StateError('Not enough stock for ${it.productName}');
        }
      }
      final saleId = await txn.insert('sales', {
        'staff_name': staffName,
        'total': total,
        'profit': profit,
        'payment_method': paymentMethod,
        'payment_reference': paymentReference,
        'amount_tendered': paid,
        'change_given': change,
        'created_at': now,
      });
      for (final it in items) {
        final fraction = it.portion == 'half'
            ? 0.5
            : it.portion == 'quarter'
                ? 0.25
                : 1.0;
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

  Future<List<Sale>> getSales({DateTime? since, String? staffName}) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];
    if (since != null) {
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
    );
    if (rows.isEmpty) return [];
    final saleIds = rows.map((row) => row['id']).toList();
    final itemRows = await db.query(
      'sale_items',
      where: 'sale_id IN (${List.filled(saleIds.length, '?').join(',')})',
      whereArgs: saleIds,
    );
    final itemsBySale = <dynamic, List<Map<String, dynamic>>>{};
    for (final item in itemRows) {
      (itemsBySale[item['sale_id']] ??= []).add(item);
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
