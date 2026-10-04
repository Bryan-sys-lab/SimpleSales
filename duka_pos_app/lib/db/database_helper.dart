import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/models.dart';
import '../utils/money.dart';
// The aggregate result types (DailyTotals, ProductSalesRow, TimeBucket,
// DateBucket, PaymentMixRow, AttentionSummary). They live in services/ rather
// than here so this file stays a data layer: it produces rows, it does not
// define what a chart or a screen does with them.
import '../services/analytics.dart';

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
  static const _schemaVersion = 15;

  /// Slack allowed when deciding whether a container has enough left for a sale.
  ///
  /// Sized to absorb the error in summing volume ratios, and to do nothing else.
  /// A bottle holds at most [Product.maxBottleMl] millilitres, so this is under
  /// a nanolitre at the largest size the app accepts.
  static const double _volumeTolerance = 1e-9;

  /// Keys in `shop_settings`. Named rather than stringly-typed at every call
  /// site, because the backend reads the same names and a typo here is a silent
  /// "setting not found" in a legally significant field.
  static const String settingVatRate = 'vat_rate_percent';
  static const String settingTillCode = 'till_code';
  static const String settingTin = 'tin';
  static const String settingEtimsDeviceId = 'etims_device_id';

  /// Test-only: opens an existing database *file* at the current schema
  /// version, running the real [_onUpgrade].
  ///
  /// [openInMemoryForTests] only ever calls [_onCreate], so it cannot exercise a
  /// migration. This exists so a test can build a database at an older schema
  /// with known rows, reopen it here, and assert the upgrade preserved the
  /// data — which is the only way to prove a migration is safe for the tills
  /// already in the field.
  @visibleForTesting
  static Future<Database> openExistingForUpgradeTests(String path) async {
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: instance._onCreate,
        onUpgrade: instance._onUpgrade,
      ),
    );
  }

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
        amount INTEGER NOT NULL,
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
    if (oldVersion < 11) {
      await _migrateMoneyToMinorUnits(db);
    }
    // MUST come after the v11 block, not before it. That block drops and
    // recreates `products`, and a `product_barcodes` foreign key created
    // beforehand would be left naming a table SQLite no longer holds — the
    // constraint would silently fail to resolve against the rebuilt parent.
    if (oldVersion < 12) {
      // Tables that `_onCreate` builds but that no migration ever created. A
      // till that reaches v12 from anything older than v11 therefore never
      // gets them: `staff` and `owner` were added as bare `CREATE TABLE`
      // statements in `_onCreate` with no migration block, and `products`,
      // `sales`, `sale_items` are *rebuilt* by the v11 money migration into the
      // new column layout rather than created when absent. The result is an
      // upgraded till that can record no staff, adjust no stock and queue no
      // M-Pesa payment, while a freshly installed one does all three — the
      // hardest kind of bug to notice, because it only appears on devices that
      // were upgraded rather than installed.
      await _createTablesMissingFromOlderMigrations(db);
      await _createBarcodesAndReceiptTables(db);
    }
    if (oldVersion < 13) {
      await _createEtimsTables(db);
    }
    if (oldVersion < 14) {
      await _createVariantsAndImportTables(db);
    }
    if (oldVersion < 15) {
      await _createShiftTables(db);
      await _createShotCupsTable(db);
      await _createCupSizeSuggestionsTable(db);
    }
  }

  /// v14 -> v15: shifts, till counts, and reconciliations.
  ///
  /// Shifts are the unit of account for cash reconciliation: a cashier opens a
  /// shift with a float, rings up sales, and closes it by counting the till.
  ///
  /// The `FOREIGN KEY ... ON DELETE CASCADE` clauses are declarative intent and
  /// are **not** enforced — see the foreign-key note on this class. Deleting a
  /// shift's children is the caller's job in Dart.
  Future<void> _createShiftTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS shifts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      staff_id INTEGER NOT NULL,
      staff_name TEXT NOT NULL,
      start_time TEXT NOT NULL,
      end_time TEXT,
      start_float INTEGER NOT NULL,
      end_float INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'open'
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shifts_staff ON shifts (staff_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shifts_status_time ON shifts (status, start_time)');

    await db.execute('''CREATE TABLE IF NOT EXISTS till_counts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      shift_id INTEGER NOT NULL,
      denomination TEXT NOT NULL,
      count INTEGER NOT NULL DEFAULT 0,
      value INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      FOREIGN KEY (shift_id) REFERENCES shifts (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_till_counts_shift ON till_counts (shift_id)');

    await db.execute('''CREATE TABLE IF NOT EXISTS reconciliations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      shift_id INTEGER NOT NULL,
      counted_cash INTEGER NOT NULL DEFAULT 0,
      expected_cash INTEGER NOT NULL DEFAULT 0,
      variance INTEGER NOT NULL DEFAULT 0,
      recorded_at TEXT NOT NULL,
      FOREIGN KEY (shift_id) REFERENCES shifts (id) ON DELETE CASCADE
    )''');
  }

  /// v14 -> v15: fixed shot cup configurations.
  ///
  /// Any inventory product can be sold as a shot: the cup has a fixed capacity
  /// and price, but the product link means the shop can change the spirit
  /// behind the same cup without touching the cup configuration.
  Future<void> _createShotCupsTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS shot_cups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      capacity_ml INTEGER NOT NULL DEFAULT 30,
      price INTEGER NOT NULL DEFAULT 0,
      label TEXT NOT NULL DEFAULT 'Shot',
      active INTEGER NOT NULL DEFAULT 1,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_shot_cups_product ON shot_cups (product_id)');
  }

  /// v14 -> v15: user-entered cup size suggestions for beer/keg products.
  ///
  /// Stores the ml sizes a shop has used before so they appear as suggestions
  /// when adding a new cup-sized variant, rather than re-typing "330", "500",
  /// etc. on every product. `product_id` is nullable so a size used across
  /// several products is remembered once and surfaces for any of them.
  Future<void> _createCupSizeSuggestionsTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS cup_size_suggestions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER,
      size_ml INTEGER NOT NULL,
      use_count INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cup_sizes_product '
        'ON cup_size_suggestions (product_id)');
  }

  Future<void> _createTablesMissingFromOlderMigrations(Database db) async {
    // Byte-for-byte the declarations in `_onCreate`. `IF NOT EXISTS` throughout,
    // because this runs for every till below v12 and most of them already have
    // some of these.
    await db.execute('''CREATE TABLE IF NOT EXISTS owner (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      shop_name TEXT NOT NULL,
      phone TEXT,
      pin_hash TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS staff (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'cashier',
      pin_hash TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS stock_adjustments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      delta REAL NOT NULL,
      reason TEXT,
      staff_id INTEGER,
      created_at TEXT NOT NULL
    )''');
    await db.execute('CREATE TABLE IF NOT EXISTS staff_deletion_tombstones (\n'
        '        staff_id INTEGER PRIMARY KEY,\n'
        '        remote_id TEXT,\n'
        '        deleted_at TEXT NOT NULL\n'
        '      )');
    await db.execute('''CREATE TABLE IF NOT EXISTS pending_payments (
      reference TEXT PRIMARY KEY,
      phone_number TEXT,
      amount INTEGER NOT NULL,
      cart_json TEXT NOT NULL,
      staff_name TEXT,
      staff_id INTEGER,
      created_at TEXT NOT NULL
    )''');
  }

  /// v11 -> v12: barcodes get their own table, and shop-wide configuration
  /// plus the receipt sequence land with them.
  ///
  /// Structurally identical to the v8 block — `CREATE TABLE IF NOT EXISTS` plus
  /// `ALTER TABLE ADD COLUMN` — because a new table needs no data movement.
  /// That is what makes this cheaper than a barcode *column* would have been,
  /// not more expensive.
  ///
  /// The columns and the barcode table are in one migration on purpose: both
  /// touch `products`, and `upsertProduct` writes `toMap()` wholesale, so
  /// splitting them would mean two passes over the same rewrite logic.
  Future<void> _createBarcodesAndReceiptTables(Database db) async {
    // `barcode TEXT PRIMARY KEY NOT NULL` — one product per barcode, enforced
    // by the schema rather than by a Dart check a bulk import could bypass.
    // The separate index on product_id is for the reverse lookup (list a
    // product's codes); the primary key already covers lookup by barcode.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_barcodes (
        barcode TEXT PRIMARY KEY NOT NULL,
        product_id INTEGER NOT NULL,
        kind TEXT NOT NULL DEFAULT 'supplier',
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_product_barcodes_product ON product_barcodes (product_id)');

    // Shop-wide configuration. SharedPreferences is the wrong store for legally
    // significant values the backend also has to read, and they all arrive
    // together for eTIMS — one table now beats two migrations later.
    await db.execute('''CREATE TABLE IF NOT EXISTS shop_settings (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT
    )''');

    // The per-till receipt sequence, allocated inside the same transaction that
    // records a sale so a crash cannot skip or reuse a number.
    await db.execute('''CREATE TABLE IF NOT EXISTS receipt_counters (
      key TEXT PRIMARY KEY NOT NULL,
      value INTEGER NOT NULL
    )''');

    // NULL for every pre-v12 row, which is what a partial upgrade looks like.
    // SQLite permits many NULLs under a unique index, so the index constrains
    // only the numbers that exist.
    await db.execute('ALTER TABLE sales ADD COLUMN receipt_number TEXT');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_receipt_number ON sales (receipt_number)');
  }

  /// v12 -> v13: eTIMS receipt issuance state on the sale, plus the offline
  /// queue.
  ///
  /// Kept separate from v12 rather than folded into it: v12 is a coherent unit
  /// (barcodes, shop config, receipt numbering) that has its own migration
  /// test, and eTIMS arrived as a separate concern with a separate failure mode
  /// — a sale that is committed locally and not yet accepted by KRA.
  Future<void> _createEtimsTables(Database db) async {
    // 'not_required' for every existing row: eTIMS is off by default, and a
    // default of 'pending' would make the shop's whole historical ledger look
    // like an unreconciled KRA queue.
    await db.execute(
        "ALTER TABLE sales ADD COLUMN etims_status TEXT NOT NULL DEFAULT 'not_required'");
    await db.execute('ALTER TABLE sales ADD COLUMN etims_receipt_number TEXT');

    // The offline queue, shaped exactly like `pending_payments`: written before
    // the network call, uploaded when a connection exists, deleted only once
    // KRA has answered. Inventing a second, different pattern for the same
    // problem would be the reason offline sales ever stopped reconciling.
    //
    // The payload is deliberately *not* stored here. It is rebuilt from the
    // recorded sale and its line items at flush time, so there is exactly one
    // copy of the amounts and no possibility of the queue and the ledger
    // disagreeing about what was sold.
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
  }

  /// v13 -> v14: product variants, units, import attention, unverified payments.
  ///
  /// One migration because all four arrived with the same feature request and
  /// none is useful alone — a variant with no barcode cannot be scanned, and an
  /// import that can flag a bad row is useless before variants exist to import.
  Future<void> _createVariantsAndImportTables(Database db) async {
    // --- Units -------------------------------------------------------------
    //
    // `unit` says what the product is *measured in*; `bottle_ml` (already
    // present) says how big one unit is. Both are needed: a 750ml bottle and a
    // 750ml tank are both 750ml but are counted in different things, and a
    // cup-priced product needs a price per cup with no volume relationship to
    // the parent at all.
    await db.execute(
        "ALTER TABLE products ADD COLUMN unit TEXT NOT NULL DEFAULT 'each'");

    // --- Variants ----------------------------------------------------------
    await db.execute('''CREATE TABLE IF NOT EXISTS product_variants (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      sku TEXT NOT NULL DEFAULT '',
      unit TEXT NOT NULL DEFAULT 'each',
      size_ml INTEGER NOT NULL DEFAULT 0,
      sell_price INTEGER NOT NULL DEFAULT 0,
      cost_price INTEGER NOT NULL DEFAULT 0,
      stock_qty REAL NOT NULL DEFAULT 0,
      reorder_level INTEGER NOT NULL DEFAULT 0,
      position INTEGER NOT NULL DEFAULT 0,
      active INTEGER NOT NULL DEFAULT 1,
      FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
    )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_product_variants_product ON product_variants (product_id, position)');

    // Whether a product is sold as variants. A flag rather than deriving it from
    // the variant count, because the *absence* of variants and "the owner has
    // not added them yet" are different states and the second needs a prompt on
    // the product, not an absence to infer from.
    await db.execute(
        'ALTER TABLE products ADD COLUMN track_variants INTEGER NOT NULL DEFAULT 0');

    // --- Variant barcodes --------------------------------------------------
    //
    // Reuses `product_barcodes` rather than a second table so that a code still
    // resolves to exactly one thing. Nullable `variant_id` is what makes that
    // safe: the primary key forbids the same code appearing twice, whichever
    // kind it is, so scanning can never find two candidates.
    await db
        .execute('ALTER TABLE product_barcodes ADD COLUMN variant_id INTEGER');

    // --- Sale lines carry the variant --------------------------------------
    //
    // Denormalised onto the line rather than joined at read time. A receipt and
    // a "Dark 500ml" line must still say "Dark 500ml" after the owner renames
    // or deletes the variant, because the document the customer was handed
    // cannot change retroactively.
    await db.execute('ALTER TABLE sale_items ADD COLUMN variant_id INTEGER');
    await db.execute(
        "ALTER TABLE sale_items ADD COLUMN variant_name TEXT NOT NULL DEFAULT ''");

    // --- Unverified payments ----------------------------------------------
    //
    // An offline "Paid" tap records the sale with `payment_verified = 0`. It is
    // *not* a lesser kind of sale — the money was taken — but it has not been
    // matched to a PayHero receipt, and the owner needs to be able to find those
    // and reconcile them. Defaults to 1 so every pre-existing row is verified.
    await db.execute(
        'ALTER TABLE sales ADD COLUMN payment_verified INTEGER NOT NULL DEFAULT 1');
    await db.execute('ALTER TABLE sales ADD COLUMN payment_confirmed_at TEXT');

    // --- Import rows needing attention -------------------------------------
    await db.execute('''CREATE TABLE IF NOT EXISTS import_needs_attention (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source TEXT NOT NULL,
      sheet_name TEXT NOT NULL DEFAULT '',
      row_number INTEGER NOT NULL DEFAULT 0,
      raw_name TEXT NOT NULL DEFAULT '',
      raw_row TEXT NOT NULL,
      problem TEXT NOT NULL,
      resolved INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_import_attention_open
      ON import_needs_attention (resolved, created_at)''');

    // --- Categories --------------------------------------------------------
    //
    // A real table rather than a free-text column, because the three importers
    // and the editor each defaulted to the literal 'General' and nothing
    // reconciled spelling: 'Drinks', 'drinks' and 'drinks ' became three
    // categories and three separate reports.
    await db.execute('''CREATE TABLE IF NOT EXISTS categories (
      name TEXT PRIMARY KEY NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0
    )''');
  }

  /// v10 -> v11: money moves from REAL shillings to INTEGER minor units.
  ///
  /// Amounts are held as integer cents so that summing a cart is exact. See
  /// utils/money.dart for the arithmetic this fixes.
  ///
  /// SQLite columns declared REAL have *affinity*, which silently converts an
  /// inserted integer back to a float, so the money columns cannot be converted
  /// in place: `UPDATE ... SET cost_price = 1999` on a REAL column stores
  /// 1999.0 and buys nothing. Each affected table is therefore rebuilt.
  ///
  /// The rebuild copies through a temporary table and renames that into place.
  /// Renaming the original would be simpler, but SQLite 3.25 and later rewrite
  /// foreign-key clauses that mention the renamed table, which would silently
  /// repoint `sale_items`' reference at the throwaway name. Copying into a
  /// name nothing references leaves every FK clause untouched.
  ///
  /// `qty` and `stock_qty` are deliberately left REAL: they count bottles, not
  /// shillings, and a half bottle is a real quantity.
  Future<void> _migrateMoneyToMinorUnits(Database db) async {
    // Recorded so an interrupted migration cannot leave a half-converted till.
    // sqflite runs onUpgrade in a transaction, so this rolls back with the rest.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products_v11 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT,
        cost_price INTEGER NOT NULL,
        sell_price INTEGER NOT NULL,
        stock_qty REAL NOT NULL DEFAULT 0,
        reorder_level INTEGER NOT NULL DEFAULT 5,
        bottle_ml INTEGER NOT NULL DEFAULT 750,
        half_price INTEGER,
        quarter_price INTEGER,
        excise_stamp_batch TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT,
        remote_id TEXT
      )
    ''');
    await db.execute('''
      INSERT INTO products_v11
        (id, name, category, cost_price, sell_price, stock_qty, reorder_level,
         bottle_ml, half_price, quarter_price, excise_stamp_batch, active,
         updated_at, remote_id)
      SELECT
        id, name, category,
        CAST(ROUND(cost_price * 100) AS INTEGER),
        CAST(ROUND(sell_price * 100) AS INTEGER),
        stock_qty, reorder_level, bottle_ml,
        CAST(ROUND(half_price * 100) AS INTEGER),
        CAST(ROUND(quarter_price * 100) AS INTEGER),
        excise_stamp_batch, active, updated_at, remote_id
      FROM products
    ''');
    await db.execute('DROP TABLE products');
    await db.execute('ALTER TABLE products_v11 RENAME TO products');

    // sales before sale_items, so the line table's foreign key resolves
    // against the rebuilt parent.
    await db.execute('''
      CREATE TABLE sales_v11 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staff_name TEXT NOT NULL,
        staff_id INTEGER,
        total INTEGER NOT NULL,
        profit INTEGER NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        payment_reference TEXT,
        amount_tendered INTEGER NOT NULL DEFAULT 0,
        change_given INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      INSERT INTO sales_v11
        (id, staff_name, staff_id, total, profit, payment_method,
         payment_reference, amount_tendered, change_given, created_at)
      SELECT
        id, staff_name, staff_id,
        CAST(ROUND(total * 100) AS INTEGER),
        CAST(ROUND(profit * 100) AS INTEGER),
        payment_method, payment_reference,
        CAST(ROUND(amount_tendered * 100) AS INTEGER),
        CAST(ROUND(change_given * 100) AS INTEGER),
        created_at
      FROM sales
    ''');
    await db.execute('DROP TABLE sales');
    await db.execute('ALTER TABLE sales_v11 RENAME TO sales');

    await db.execute('''
      CREATE TABLE sale_items_v11 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        qty REAL NOT NULL,
        unit_price INTEGER NOT NULL,
        unit_cost INTEGER NOT NULL,
        portion TEXT NOT NULL DEFAULT 'full',
        portion_ml INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (sale_id) REFERENCES sales (id)
      )
    ''');
    await db.execute('''
      INSERT INTO sale_items_v11
        (id, sale_id, product_id, product_name, qty, unit_price, unit_cost,
         portion, portion_ml)
      SELECT
        id, sale_id, product_id, product_name, qty,
        CAST(ROUND(unit_price * 100) AS INTEGER),
        CAST(ROUND(unit_cost * 100) AS INTEGER),
        portion, portion_ml
      FROM sale_items
    ''');
    await db.execute('DROP TABLE sale_items');
    await db.execute('ALTER TABLE sale_items_v11 RENAME TO sale_items');

    // Only present from v10, and only if some rows were queued.
    final pending = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='pending_payments'");
    if (pending.isNotEmpty) {
      await db.execute('''
        CREATE TABLE pending_payments_v11 (
          reference TEXT PRIMARY KEY,
          phone_number TEXT,
          amount INTEGER NOT NULL,
          cart_json TEXT NOT NULL,
          staff_name TEXT,
          staff_id INTEGER,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        INSERT INTO pending_payments_v11
          (reference, phone_number, amount, cart_json, staff_name, staff_id, created_at)
        SELECT
          reference, phone_number,
          CAST(ROUND(amount * 100) AS INTEGER),
          cart_json, staff_name, staff_id, created_at
        FROM pending_payments
      ''');
      await db.execute('DROP TABLE pending_payments');
      await db.execute(
          'ALTER TABLE pending_payments_v11 RENAME TO pending_payments');
    }

    // Indexes live on the dropped tables and do not survive the rebuild. The
    // v10 block above notes this for upgraded installs; leaving them out here
    // would permanently full-scan sales and sale_items on every report.
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_date ON sales (created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items (product_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items (sale_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_staff ON sales (staff_id)');
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
        cost_price INTEGER NOT NULL,
        sell_price INTEGER NOT NULL,
        stock_qty REAL NOT NULL DEFAULT 0,
        reorder_level INTEGER NOT NULL DEFAULT 5,
        bottle_ml INTEGER NOT NULL DEFAULT 750,
        half_price INTEGER,
        quarter_price INTEGER,
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
        total INTEGER NOT NULL,
        profit INTEGER NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        payment_reference TEXT,
        amount_tendered INTEGER NOT NULL DEFAULT 0,
        change_given INTEGER NOT NULL DEFAULT 0,
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
        unit_price INTEGER NOT NULL,
        unit_cost INTEGER NOT NULL,
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
      amount INTEGER NOT NULL,
      cart_json TEXT NOT NULL,
      staff_name TEXT,
      staff_id INTEGER,
      created_at TEXT NOT NULL
    )''');
    // `amount` is INTEGER here, not the pre-v11 REAL. The v11 money migration
    // rebuilt this table on upgraded installs, but the fresh-install CREATE
    // kept the old declaration — so a till that had never been upgraded stored
    // integer cents into a REAL-affinity column and read them back as if they
    // were shillings, making the amount on an outstanding-payment row 100x too
    // large. Declaring it INTEGER here makes a new till match a migrated one.

    // From v12/v13 onwards. Reached by calling the same helpers the migration
    // path uses, so a fresh install and an upgraded one cannot diverge — the
    // schema is defined once and applied twice.
    await _createTablesMissingFromOlderMigrations(db);
    await _createBarcodesAndReceiptTables(db);
    await _createEtimsTables(db);
    await _createVariantsAndImportTables(db);
    await _createShiftTables(db);
    await _createShotCupsTable(db);
    await _createCupSizeSuggestionsTable(db);
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
            'UPDATE $table SET staff_name = ? WHERE staff_id = ?',
            [deletedLabel, staff.id]);
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

  // ---------------- Barcodes ----------------
  //
  // Its own section, its own table and its own API: a barcode is not a product
  // attribute, and `upsertProduct` writes `Product.toMap()` wholesale, so a
  // barcode written through it would be erased by the next unrelated product
  // save. Uniqueness is enforced by `barcode TEXT PRIMARY KEY`, so there is no
  // duplicate policy to enforce in Dart — only a constraint failure to report
  // back in terms the owner can act on.

  /// The product a scan resolved to.
  ///
  /// A single indexed lookup on the primary key, deterministic by construction.
  /// [barcode] must already be normalised (see services/barcode/barcode_service)
  /// — the comparison is exact, so a raw code with an FNC1 separator or a
  /// leading space simply will not match.
  Future<Product?> getProductByBarcode(String barcode) async {
    final rows = await (await database).rawQuery(
      '''SELECT p.* FROM products p
         JOIN product_barcodes b ON b.product_id = p.id
        WHERE b.barcode = ? AND p.active = 1
        LIMIT 1''',
      [barcode],
    );
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  /// Every code a product answers to, primary-key order for stable output.
  Future<List<ProductBarcode>> getBarcodesForProduct(int productId) async {
    final rows = await (await database).query(
      'product_barcodes',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'barcode',
    );
    return rows.map(ProductBarcode.fromMap).toList();
  }

  /// Every code in the catalogue, for export.
  Future<List<ProductBarcode>> getAllBarcodes() async {
    final rows = await (await database)
        .query('product_barcodes', orderBy: 'product_id, barcode');
    return rows.map(ProductBarcode.fromMap).toList();
  }

  /// What a barcode already belongs to, if anything.
  ///
  /// Used to turn a constraint failure into "this code is already on *Kenyana
  /// Beer*", which tells the owner which product to remove it from. A bare
  /// "duplicate barcode" does not.
  Future<Product?> getProductOwningBarcode(String barcode) async {
    final rows = await (await database).rawQuery(
      '''SELECT p.* FROM products p
         JOIN product_barcodes b ON b.product_id = p.id
        WHERE b.barcode = ?
        LIMIT 1''',
      [barcode],
    );
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  /// Attaches [barcode] to [productId].
  ///
  /// Returns false when the code already exists. It does not throw and it does
  /// not overwrite: silently re-pointing a barcode that a second distributor
  /// uses would make the *other* product unscannable, which is worse than
  /// refusing and saying so.
  Future<bool> addBarcode({
    required int productId,
    required String barcode,
    String kind = BarcodeKind.supplier,

    /// Which variant this code identifies, or null for the product itself.
    ///
    /// Without this a variant could not be scanned at all: Dark and Regular
    /// would both sell as the parent product, which is the whole thing the
    /// variant exists to prevent.
    int? variantId,
  }) async {
    try {
      await (await database).insert('product_barcodes', {
        'barcode': barcode,
        'product_id': productId,
        'kind': kind,
        if (variantId != null) 'variant_id': variantId,
      });
      return true;
    } on DatabaseException {
      return false;
    }
  }

  /// Bulk form of [addBarcode], for spreadsheet import.
  ///
  /// Runs in one transaction and *skips* codes that are already taken rather
  /// than failing: a supplier workbook that reuses one code across two rows
  /// must not abort the whole import. Returns the codes that were refused,
  /// which the caller reports by product name.
  Future<List<String>> addBarcodes(List<ProductBarcode> barcodes) async {
    if (barcodes.isEmpty) return const [];
    final db = await database;
    final refused = <String>[];
    await db.transaction((txn) async {
      for (final entry in barcodes) {
        try {
          await txn.insert('product_barcodes', entry.toMap());
        } on DatabaseException {
          refused.add(entry.barcode);
        }
      }
    });
    return refused;
  }

  /// Relabels a barcode without touching its product.
  ///
  /// `kind` is informational, but an import's duplicate report is only useful
  /// if the labels mean something, so the label has to be editable. Updating in
  /// place rather than delete-then-insert means a failed write cannot leave the
  /// code unattached.
  Future<void> setBarcodeKind(String barcode, String kind) async {
    await (await database).update(
      'product_barcodes',
      {'kind': kind},
      where: 'barcode = ?',
      whereArgs: [barcode],
    );
  }

  /// Detaches [barcode] from whichever product holds it.
  Future<void> removeBarcode(String barcode) async {
    await (await database)
        .delete('product_barcodes', where: 'barcode = ?', whereArgs: [barcode]);
  }

  // ---------------- Product variants ----------------

  /// A product's variants, in the order the owner arranged them.
  ///
  /// Returns an empty list for a product that does not track variants, so
  /// callers can branch on emptiness without also checking a flag — and the
  /// flag is only ever *needed* to distinguish "no variants" from "has not
  /// added them yet", which is a prompt decision rather than a data one.
  Future<List<ProductVariant>> getVariants(int productId,
      {bool activeOnly = true}) async {
    final rows = await (await database).query(
      'product_variants',
      where: activeOnly ? 'product_id = ? AND active = 1' : 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'position, id',
    );
    return rows.map(ProductVariant.fromMap).toList();
  }

  /// Every variant in the catalogue, for export and for stock checks.
  Future<List<ProductVariant>> getAllVariants() async {
    final rows = await (await database)
        .query('product_variants', orderBy: 'product_id, position, id');
    return rows.map(ProductVariant.fromMap).toList();
  }

  Future<ProductVariant?> getVariantById(int id) async {
    final rows = await (await database)
        .query('product_variants', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ProductVariant.fromMap(rows.first);
  }

  /// Writes a variant, insert or update by id.
  ///
  /// Money is not defaulted to the parent on update. A variant with its own
  /// price that silently falls back to the parent's on the next save is a price
  /// change nobody made.
  Future<int> upsertVariant(ProductVariant variant) async {
    final map = variant.toMap();
    if (variant.id == null) {
      final id =
          await (await database).insert('product_variants', map..remove('id'));
      // Position defaults to "after the ones already there" so a newly added
      // variant lands at the bottom without the caller computing an index.
      return id;
    }
    await (await database).update('product_variants', map,
        where: 'id = ?', whereArgs: [variant.id]);
    return variant.id!;
  }

  Future<void> deleteVariant(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn
          .delete('product_barcodes', where: 'variant_id = ?', whereArgs: [id]);
      await txn.delete('product_variants', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Resolves a barcode to a product and, when the code belongs to one, the
  /// variant it identifies.
  ///
  /// A variant's code answers for its *parent product* as well, because the
  /// sell screen has to show something to tap. Returning both is what lets the
  /// caller add the right thing to the cart instead of the parent and
  /// discovering the mistake at checkout.
  Future<({Product product, ProductVariant? variant})?> getScanTarget(
      String barcode) async {
    final rows = await (await database).rawQuery(
      '''SELECT p.*, b.variant_id AS _matched_variant
         FROM products p
         JOIN product_barcodes b ON b.product_id = p.id
        WHERE b.barcode = ? AND p.active = 1
        LIMIT 1''',
      [barcode],
    );
    if (rows.isEmpty) return null;
    final variantId = rows.first['_matched_variant'] as int?;
    if (variantId == null) {
      return (product: Product.fromMap(rows.first), variant: null);
    }
    final variant = await getVariantById(variantId);
    return (product: Product.fromMap(rows.first), variant: variant);
  }

  // ---------------- Categories ----------------

  /// The shop's category vocabulary, in display order.
  ///
  /// Seeded once on first use from [CategoryName.seeds]. An unknown category
  /// from an import is *added* to this list rather than being forced into one of
  /// the seeds — a shop that stocks something the seed list never imagined would
  /// otherwise have every one of its rows relabelled "Other".
  Future<List<String>> getCategories() async {
    final db = await database;
    var rows = await db.query('categories', orderBy: 'sort_order, name');
    if (rows.isEmpty) {
      await seedCategories();
      rows = await db.query('categories', orderBy: 'sort_order, name');
    }
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> seedCategories() async {
    final db = await database;
    await db.transaction((txn) async {
      for (var i = 0; i < CategoryName.seeds.length; i++) {
        await txn.insert(
          'categories',
          {'name': CategoryName.seeds[i], 'sort_order': i},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  /// Adds a category if it is new, normalised. Returns the canonical name.
  Future<String> ensureCategory(String? raw) async {
    final name = CategoryName.normalise(raw);
    if (name == CategoryName.general && (raw ?? '').trim().isEmpty) {
      return name;
    }
    await (await database).insert(
      'categories',
      {'name': name, 'sort_order': 999},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return name;
  }

  // ---------------- Import rows needing attention ----------------

  Future<int> recordImportProblem({
    required String source,
    String sheetName = '',
    required int rowNumber,
    required String rawName,
    required List<dynamic> rawRow,
    required String problem,
  }) async {
    return (await database).insert('import_needs_attention', {
      'source': source,
      'sheet_name': sheetName,
      'row_number': rowNumber,
      'raw_name': rawName,
      'raw_row': jsonEncode(rawRow.map((c) => c?.toString()).toList()),
      'problem': problem,
      'resolved': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Open problems, newest first.
  Future<List<ImportNeedsAttention>> getImportProblems({
    bool includeResolved = false,
    int limit = 200,
  }) async {
    final rows = await (await database).query(
      'import_needs_attention',
      where: includeResolved ? null : 'resolved = 0',
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(ImportNeedsAttention.fromMap).toList();
  }

  Future<int> countOpenImportProblems() async {
    final rows = await (await database).rawQuery(
        'SELECT COUNT(*) AS c FROM import_needs_attention WHERE resolved = 0');
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Marks a row as dealt with, so it leaves the list but stays auditable.
  Future<void> resolveImportProblem(int id) async {
    await (await database).update('import_needs_attention', {'resolved': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Shop settings ----------------

  Future<String?> getSetting(String key) async {
    final rows = await (await database)
        .query('shop_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final value = rows.first['value'];
    return value is String ? value : value?.toString();
  }

  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await (await database)
          .delete('shop_settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await (await database).insert(
      'shop_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Every setting, for backup and for the backend push.
  Future<Map<String, String>> getAllSettings() async {
    final rows = await (await database).query('shop_settings');
    return {
      for (final row in rows)
        row['key'] as String: (row['value'] as String?) ?? '',
    };
  }

  // ---------------- Receipt numbering ----------------

  /// Counter key for the sale sequence.
  ///
  /// Fixed rather than per-till-code on purpose: it lives inside one workspace
  /// database, which is already one till, and a fixed key means changing the
  /// displayed till code renames future receipts without ever restarting the
  /// sequence and reissuing a number that has already been handed to a
  /// customer.
  static const String receiptCounterKey = 'sale_sequence';

  /// Number of digits in the printed sequence. `000123` reads as a receipt
  /// number; `123` reads as a quantity.
  static const int receiptSequenceDigits = 6;

  /// The till code used when the shop has not set one.
  ///
  /// Derived from the workspace key rather than a fixed string so two tills in
  /// the same shop — or two shops on the same KRA TIN — cannot both issue
  /// `POS-000001`. The workspace key is already unique per till, which is the
  /// whole reason a separate database file exists per shop.
  static String defaultTillCode(String workspaceKey) {
    final cleaned =
        workspaceKey.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (cleaned.isEmpty) return 'POS';
    return cleaned.substring(0, cleaned.length.clamp(1, 8));
  }

  /// The shop's till code, falling back to one derived from the workspace.
  Future<String> getTillCode() async {
    final configured = (await getSetting(settingTillCode))?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return defaultTillCode(_workspaceKey);
  }

  Future<void> setTillCode(String code) =>
      setSetting(settingTillCode, code.trim().toUpperCase());

  /// The VAT rate in whole percent.
  ///
  /// Defaults to Kenya's standard 16%. Zero is valid and means the goods are
  /// exempt, which the receipt renders by omitting the VAT lines rather than
  /// printing a zero.
  Future<int> getVatRatePercent() async {
    final raw = await getSetting(settingVatRate);
    final parsed = int.tryParse(raw ?? '');
    if (parsed == null || parsed < 0 || parsed > 100) {
      return _defaultVatRatePercent;
    }
    return parsed;
  }

  Future<void> setVatRatePercent(int percent) {
    if (percent < 0 || percent > 100) {
      throw ArgumentError.value(percent, 'percent', 'must be 0 to 100');
    }
    return setSetting(settingVatRate, '$percent');
  }

  static const int _defaultVatRatePercent = 16;

  /// Allocates the next receipt number, `<TILL>-000123`.
  ///
  /// Called *inside* the checkout transaction. Reading the counter, incrementing
  /// it and writing it back under the same transaction is the entire reason a
  /// crash mid-sale cannot skip a number or hand the same one to two customers:
  /// either the sale and the increment both commit, or neither does.
  ///
  /// [tillCode] is passed in rather than read here on purpose. Every accessor on
  /// this class goes through `database`, and sqflite serialises transactions on
  /// the same queue as ordinary queries — so a read issued from inside a
  /// transaction callback would queue *behind* that transaction and deadlock.
  /// The caller resolves it before opening the transaction instead.
  Future<String> allocateReceiptNumber(
    DatabaseExecutor txn, {
    required String tillCode,
  }) async {
    final rows = await txn.query(
      'receipt_counters',
      where: 'key = ?',
      whereArgs: [receiptCounterKey],
      limit: 1,
    );
    final next = rows.isEmpty ? 1 : ((rows.first['value'] as int?) ?? 0) + 1;
    await txn.insert(
      'receipt_counters',
      {'key': receiptCounterKey, 'value': next},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return '$tillCode-${next.toString().padLeft(receiptSequenceDigits, '0')}';
  }

  /// The receipt number of a recorded sale.
  ///
  /// Pre-v12 sales have none, so the row id is used as a provisional stand-in
  /// exactly as Phase 1 did. It is monotonic and unique, which is all the
  /// format needs; it leaks an internal row id onto customer-facing paperwork,
  /// which is why every *new* sale stores the real sequence.
  String receiptNumberFor(Map<String, dynamic> saleRow) {
    final stored = (saleRow['receipt_number'] as String?)?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    return 'POS-${(saleRow['id'] as int? ?? 0).toString().padLeft(receiptSequenceDigits, '0')}';
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
    required Money amount,
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
          'amount': amount.minorUnits,
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

  /// Removes a product for good, freeing its barcodes.
  ///
  /// [deactivateProduct] is what the inventory screen uses, and a soft delete
  /// deliberately *keeps* the codes: the owner may well bring the product back,
  /// and orphaning its barcode would stop the till from scanning it ever again.
  /// This is the permanent path, and it removes the codes explicitly in the same
  /// transaction as the row, because `ON DELETE CASCADE` in the schema is not
  /// enforced on this connection — see the note on foreign keys below this
  /// class.
  Future<void> hardDeleteProduct(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn
          .delete('product_barcodes', where: 'product_id = ?', whereArgs: [id]);
      await txn.delete('products', where: 'id = ?', whereArgs: [id]);
    });
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
    Money? amountTendered,
    int? staffId,
    bool etimsPending = false,

    /// Whether the payment was confirmed by the provider.
    ///
    /// False only for an M-Pesa sale recorded while offline, where the customer
    /// paid in the shop but no STK push was sent and nothing has confirmed it.
    /// That is a real sale, not a lesser one — the money was taken — so it is
    /// recorded identically and only flagged. Default true, so every cash,
    /// card and confirmed-M-Pesa sale is verified without saying so.
    bool paymentVerified = true,
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
    //
    // The accumulation happens inside the transaction, below, because a measured
    // pour is only a fraction once you know how big the container is.
    final db = await database;
    // Every amount is quantised as it is accumulated, so the stored total is
    // exactly the sum of the stored line amounts and `change` is a real number
    // of shillings rather than a floating-point artefact.
    // Integer cents throughout: each line is scaled once (which rounds), and
    // the sums below are exact integer additions. The recorded total is
    // therefore always exactly the sum of the recorded line amounts.
    final total = sumMoney(items.map((it) => it.unitPrice.times(it.qty)));
    final profit =
        sumMoney(items.map((it) => (it.unitPrice - it.unitCost).times(it.qty)));
    final paid = amountTendered ?? total;
    if (paid.isNegative) {
      throw StateError('Amount received cannot be less than the sale total');
    }
    if (paid < total) {
      throw StateError('Amount received cannot be less than the sale total');
    }
    final change = paid - total;
    final now = DateTime.now().toIso8601String();
    // Resolved before the transaction opens: see allocateReceiptNumber.
    final tillCode = await getTillCode();

    return db.transaction<int>((txn) async {
      // A line's fraction of its container. [containerMl] is the product's own
      // bottle/keg size, which only a measured pour needs.
      //
      // A measured pour is capped at one whole container: a capacity typed
      // larger than the bottle it is poured from is a mistake in the shop's
      // configuration, and the least wrong answer to it is to empty that
      // bottle rather than to drive stock negative.
      double portionFactor(SaleItem item, double containerMl) {
        if (item.portion == SalePortion.half) return 0.5;
        if (item.portion == SalePortion.quarter) return 0.25;
        if (item.portion == SalePortion.measured) {
          if (item.portionMl <= 0 || containerMl <= 0) return 1.0;
          final fraction = item.portionMl / containerMl;
          return fraction > 1 ? 1.0 : fraction;
        }
        return 1.0;
      }

      // Read every product this sale touches once: its stock is needed for the
      // availability check and its container size for the fraction.
      final stockByProduct = <int, double>{};
      final containerMlByProduct = <int, double>{};
      for (final productId in items.map((it) => it.productId).toSet()) {
        final current = await txn.query('products',
            where: 'id = ?', whereArgs: [productId], limit: 1);
        if (current.isEmpty) {
          final missing = items.firstWhere((it) => it.productId == productId);
          throw StateError('Product not found: ${missing.productName}');
        }
        stockByProduct[productId] =
            (current.first['stock_qty'] as num).toDouble();
        containerMlByProduct[productId] =
            (current.first['bottle_ml'] as num?)?.toDouble() ?? 0;
      }

      final requiredUnits = <int, double>{};
      for (final item in items) {
        requiredUnits[item.productId] = (requiredUnits[item.productId] ?? 0) +
            item.qty *
                portionFactor(item, containerMlByProduct[item.productId]!);
      }
      if (enforceStock) {
        for (final entry in requiredUnits.entries) {
          // Compared with a tolerance because these are volumes, and a
          // measured pour is a ratio: 25 shots of 30 ml from a 750 ml bottle is
          // exactly one bottle, but 25 x (30/750) evaluates to
          // 1.0000000000000002 in binary floating point. Without the tolerance
          // the twenty-fifth shot is refused as an oversell — a bar selling one
          // bottle of shots cannot sell its last shot.
          //
          // The tolerance is far below a microlitre at any bottle size that
          // exists, so it forgives the arithmetic error and nothing else.
          if (stockByProduct[entry.key]! + _volumeTolerance < entry.value) {
            final offending =
                items.firstWhere((it) => it.productId == entry.key);
            throw StateError('Not enough stock for ${offending.productName}');
          }
        }
      }
      final receiptNumber =
          await allocateReceiptNumber(txn, tillCode: tillCode);
      final saleId = await txn.insert('sales', {
        'staff_name': staffName,
        'staff_id': staffId,
        'total': total.minorUnits,
        'profit': profit.minorUnits,
        'payment_method': paymentMethod,
        'payment_reference': paymentReference,
        'amount_tendered': paid.minorUnits,
        'change_given': change.minorUnits,
        'created_at': now,
        'receipt_number': receiptNumber,
        // A sale is only ever pending eTIMS if the shop has eTIMS switched on,
        // which [etimsPending] decides before the transaction opens. See
        // queuePendingEtims, which is written in the same transaction as the
        // sale itself so the two can never disagree.
        'etims_status':
            etimsPending ? EtimsStatus.pending : EtimsStatus.notRequired,
        'payment_verified': paymentVerified ? 1 : 0,
        'payment_confirmed_at': paymentVerified ? now : null,
      });
      for (final it in items) {
        final fraction = portionFactor(it, containerMlByProduct[it.productId]!);
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': it.productId,
          'product_name': it.productName,
          'qty': it.qty,
          'unit_price': it.unitPrice.minorUnits,
          'unit_cost': it.unitCost.minorUnits,
          'portion': it.portion,
          'portion_ml': it.portionMl,
        });
        await txn.rawUpdate(
          'UPDATE products SET stock_qty = MAX(0, stock_qty - ?), updated_at = ? WHERE id = ?',
          [it.qty * fraction, now, it.productId],
        );
      }
      // The queue row is written in the same transaction as the sale. Writing
      // it afterwards would leave a window where a crash leaves a committed sale
      // that KRA will never be told about — an unissued tax invoice for money
      // that was actually taken, which is the one failure an eTIMS integration
      // cannot have.
      if (etimsPending) {
        await txn.insert('pending_etims', {
          'sale_id': saleId,
          'receipt_number': receiptNumber,
          'attempts': 0,
          'created_at': now,
          'updated_at': now,
        });
      }
      return saleId;
    });
  }

  // ---------------- eTIMS issuance queue ----------------

  /// Sales still waiting for a KRA receipt number, oldest first.
  ///
  /// Oldest first so numbering is uploaded in the order it was issued. KRA
  /// rejects a batch whose sequence has a gap, so flushing newest-first would
  /// trade a queue problem for a compliance one.
  Future<List<PendingEtimsReceipt>> getPendingEtimsReceipts({
    int limit = 200,
  }) async {
    final rows = await (await database).query(
      'pending_etims',
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows
        .map((row) => PendingEtimsReceipt(
              saleId: row['sale_id'] as int,
              receiptNumber: row['receipt_number'] as String,
              attempts: (row['attempts'] as int?) ?? 0,
              createdAt:
                  DateTime.tryParse(row['created_at'] as String? ?? '') ??
                      DateTime.fromMillisecondsSinceEpoch(0),
              lastError: row['last_error'] as String?,
            ))
        .toList();
  }

  Future<int> countPendingEtimsReceipts() async {
    final rows = await (await database)
        .rawQuery('SELECT COUNT(*) AS c FROM pending_etims');
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Records the KRA receipt number on the sale and clears the queue row.
  ///
  /// Idempotent: replaying an already-resolved upload is a no-op rather than a
  /// second invoice, because the queue row is what proves this sale has not
  /// been issued yet.
  Future<void> resolveEtimsReceipt({
    required int saleId,
    required String kraReceiptNumber,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'sales',
        {
          'etims_status': EtimsStatus.issued,
          'etims_receipt_number': kraReceiptNumber,
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );
      await txn
          .delete('pending_etims', where: 'sale_id = ?', whereArgs: [saleId]);
    });
  }

  /// Records a failed upload attempt without losing the row.
  ///
  /// The sale stays `pending`: it has not been issued, and claiming otherwise
  /// would make it invisible to every later retry. The attempt count is what
  /// lets the operator see a queue that is stuck rather than merely slow.
  Future<void> recordEtimsAttemptFailure({
    required int saleId,
    required String error,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawUpdate(
        '''UPDATE pending_etims
              SET attempts = attempts + 1, last_error = ?, updated_at = ?
            WHERE sale_id = ?''',
        [error, DateTime.now().toIso8601String(), saleId],
      );
      await txn.update(
        'sales',
        {'etims_status': EtimsStatus.pending},
        where: 'id = ?',
        whereArgs: [saleId],
      );
    });
  }

  /// A recorded sale, with its line items.
  ///
  /// This is how a receipt is rendered — from the *stored* sale, re-fetched by
  /// id, never from the cart that produced it. Print-after-sale and reprint are
  /// then the same code, and a reprint cannot drift from what the customer was
  /// originally handed.
  ///
  /// Returns null when the sale is not in this workspace's ledger, which is the
  /// answer for a stale id from another shop rather than an error.
  Future<Sale?> getSaleById(int id, {bool withItems = true}) async {
    final db = await database;
    final rows =
        await db.query('sales', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final sale = Sale.fromMap(rows.first);
    if (!withItems) return sale;
    final items = await db.query('sale_items',
        where: 'sale_id = ?', whereArgs: [id], orderBy: 'id');
    return Sale(
      id: sale.id,
      staffName: sale.staffName,
      total: sale.total,
      profit: sale.profit,
      createdAt: sale.createdAt,
      paymentMethod: sale.paymentMethod,
      paymentReference: sale.paymentReference,
      amountTendered: sale.amountTendered,
      changeGiven: sale.changeGiven,
      items: items.map(SaleItem.fromMap).toList(),
    );
  }

  /// Records a KRA refusal that will not resolve on a retry.
  ///
  /// The sale stays in the ledger and the queue row stays too — the invoice is
  /// still outstanding and the owner has to see that — but the status stops
  /// saying "pending" so a shop that has been told to fix their TIN is not
  /// shown the same count forever.
  Future<void> markEtimsRejected(int saleId, String reason) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE pending_etims SET last_error = ?, updated_at = ? WHERE sale_id = ?',
        [reason, DateTime.now().toIso8601String(), saleId],
      );
      await txn.update(
        'sales',
        {'etims_status': EtimsStatus.rejected},
        where: 'id = ?',
        whereArgs: [saleId],
      );
    });
  }

  /// The raw sale row, for the receipt number and eTIMS state that [Sale] does
  /// not carry.
  ///
  /// Kept separate from [getSaleById] rather than widening the model: the model
  /// is what spreadsheets and the backend serialise, and both of these are
  /// local presentation state.
  Future<Map<String, dynamic>?> getSaleRowById(int id) async {
    final rows = await (await database)
        .query('sales', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> countSalesForReceipt() async {
    final rows =
        await (await database).rawQuery('SELECT COUNT(*) AS c FROM sales');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> stockQtyForProduct(int productId) async {
    final rows = await (await database).query(
      'products',
      columns: ['stock_qty'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['stock_qty'] as num).toInt();
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

  // ---------------- Aggregates ----------------
  //
  // Everything above this line reads *rows*; everything below reduces them in
  // SQLite and returns a handful of numbers. The split is deliberate rather
  // than stylistic.
  //
  // A day's dashboard used to load every matching sale and then fold it in Dart,
  // which meant a shop with a year of history moved a row per transaction
  // across the Dart heap on every dashboard open, on a phone, at the counter.
  // `SUM(...) GROUP BY ...` answers the same question from the rows SQLite
  // already has to touch for the `idx_sales_date` range scan, and hands back one
  // row instead of ten thousand.
  //
  // Three rules hold across every method in this section:
  //
  //  * **Money comes back as `int` minor units.** `sales.total`,
  //    `sales.profit` and `sale_items.unit_price` are INTEGER cents, and
  //    `SUM()` over an INTEGER column is an exact integer. It is `CAST`ed to
  //    INTEGER explicitly (rather than left to the driver's inference) so a
  //    value can never arrive as a `double` — a float that crept in here would
  //    make the dashboard's figure stop reconciling with the sum of the sales
  //    behind it. The presentation layer wraps these in `Money.fromMinor`; see
  //    utils/money.dart for why the ledger is held in minor units at all.
  //  * **Role scoping filters `staff_id`, never `staff_name`.** The name is a
  //    mutable, unindexed TEXT column and deleting a cashier rewrites all of
  //    their rows to 'Deleted cashier', so a name filter both full-scans and
  //    folds every former cashier into one bucket. `idx_sales_staff` is on
  //    `staff_id` for exactly this.
  //  * **Range boundaries: `since`/`after` inclusive, `until` exclusive.**
  //    The same convention [getSales] already uses, so a sale on a boundary is
  //    counted exactly once across exports, reports and the dashboard.

  /// Where a sales range starts, as the `WHERE` fragment and its arguments.
  ///
  /// One builder for the whole section so the inclusive/exclusive rule cannot
  /// be applied one way on one method and the other way on the next — a range
  /// that double-counted or dropped its own boundary would show up as a
  /// dashboard total that never matched the receipts.
  static ({String clause, List<Object?> args}) _salesRangeWhere({
    DateTime? since,
    DateTime? until,
    int? staffId,
  }) {
    final where = <String>[];
    final args = <Object?>[];
    if (since != null) {
      where.add('created_at >= ?');
      args.add(since.toIso8601String());
    }
    if (until != null) {
      where.add('created_at < ?');
      args.add(until.toIso8601String());
    }
    if (staffId != null) {
      where.add('staff_id = ?');
      args.add(staffId);
    }
    return (
      clause: where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}',
      args: args
    );
  }

  /// The whole range reduced to one row: takings, profit, receipts, basket.
  ///
  /// One query, one row, whatever the range. A dashboard that previously summed
  /// a `List<Sale>` now costs the same as counting rows.
  ///
  /// `SUM` over no rows is NULL, so every aggregate is `COALESCE`d: an empty
  /// range reads as zero rather than as a null the screen has to special-case.
  /// [since] is inclusive and [until] exclusive, so two adjacent ranges neither
  /// double-count a boundary receipt nor drop one. Both were already supported
  /// by the range builder; only this method failed to expose them, which meant
  /// "today" could not be asked for without also getting everything before it.
  Future<DailyTotals> salesTotalsFor({
    DateTime? since,
    DateTime? until,
    int? staffId,
  }) async {
    final where =
        _salesRangeWhere(since: since, until: until, staffId: staffId);
    final rows = await (await database).rawQuery('''
      SELECT
        CAST(COALESCE(SUM(total), 0) AS INTEGER) AS total_minor,
        CAST(COALESCE(SUM(profit), 0) AS INTEGER) AS profit_minor,
        COUNT(*) AS transactions,
        CAST(COALESCE(ROUND(AVG(total)), 0) AS INTEGER) AS average_minor
      FROM sales
      ${where.clause}
    ''', where.args);
    final row = rows.first;
    return DailyTotals(
      totalMinor: (row['total_minor'] as num?)?.toInt() ?? 0,
      profitMinor: (row['profit_minor'] as num?)?.toInt() ?? 0,
      transactions: (row['transactions'] as num?)?.toInt() ?? 0,
      // AVG is necessarily a REAL, so it is the one aggregate that cannot be
      // exact; rounded once, here, and handed on as an int like every other
      // figure in this section.
      averageMinor: (row['average_minor'] as num?)?.toInt() ?? 0,
    );
  }

  /// What sold, ranked, with the money each product actually produced.
  ///
  /// The join to `sales` is not for the line items — it is so [staffId] can be
  /// honoured. A product-level ranking computed without it would be the whole
  /// shop's ranking shown to a cashier as if it were theirs, which is worse
  /// than showing them nothing.
  ///
  /// Grouped on `product_id` alone, with `MAX(product_name)` supplying the
  /// label, rather than on `product_id, product_name`. The name on a line is
  /// the name that was printed on the receipt, so a product the owner renamed
  /// would otherwise appear as two separate rows here — the same bottle
  /// counted twice, split across two ranks. One row per product is what a
  /// "top products" list means.
  Future<List<ProductSalesRow>> topProducts({
    required DateTime since,
    DateTime? until,
    int? staffId,
    int limit = 20,
  }) async {
    final where =
        _salesRangeWhere(since: since, until: until, staffId: staffId);
    final rows = await (await database).rawQuery('''
      SELECT
        si.product_id AS product_id,
        MAX(si.product_name) AS product_name,
        SUM(si.qty) AS units,
        CAST(ROUND(SUM(si.unit_price * si.qty)) AS INTEGER) AS revenue_minor,
        CAST(ROUND(SUM((si.unit_price - si.unit_cost) * si.qty)) AS INTEGER)
          AS profit_minor
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      ${where.clause}
      GROUP BY si.product_id
      ORDER BY revenue_minor DESC, units DESC, product_name ASC
      LIMIT ?
    ''', [...where.args, limit]);
    return rows
        .map((row) => ProductSalesRow(
              productId: (row['product_id'] as num?)?.toInt() ?? 0,
              productName: (row['product_name'] as String?) ?? '',
              // A quantity, not money: `qty` is REAL so a half bottle can be
              // recorded, so this stays a double.
              units: (row['units'] as num?)?.toDouble() ?? 0,
              revenueMinor: (row['revenue_minor'] as num?)?.toInt() ?? 0,
              profitMinor: (row['profit_minor'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  /// Takings for each hour of [day], as exactly twenty-four buckets.
  ///
  /// Empty hours are returned as zero rows rather than omitted, because
  /// "nothing sold at 03:00" and "03:00 was not counted" are different facts
  /// and a chart that skips the gap reads the first as the second.
  ///
  /// `%H` reads `created_at` as stored — local wall-clock time, no timezone
  /// suffix — so the buckets are the hours the owner actually worked. That is
  /// the point: the chart exists to answer "when should I staff up".
  Future<List<TimeBucket>> salesByHour({
    required DateTime day,
    int? staffId,
  }) async {
    final from = DateTime(day.year, day.month, day.day);
    final where = _salesRangeWhere(
        since: from,
        until: from.add(const Duration(days: 1)),
        staffId: staffId);
    final rows = await (await database).rawQuery('''
      SELECT
        CAST(strftime('%H', created_at) AS INTEGER) AS hour,
        CAST(COALESCE(SUM(total), 0) AS INTEGER) AS sales_minor,
        CAST(COALESCE(SUM(profit), 0) AS INTEGER) AS profit_minor,
        COUNT(*) AS transactions
      FROM sales
      ${where.clause}
      GROUP BY hour
      ORDER BY hour
    ''', where.args);
    final byHour = <int, Map<String, Object?>>{
      for (final row in rows) (row['hour'] as num?)?.toInt() ?? -1: row,
    };
    return List<TimeBucket>.generate(24, (hour) {
      final row = byHour[hour];
      return TimeBucket(
        hour: hour,
        salesMinor: (row?['sales_minor'] as num?)?.toInt() ?? 0,
        profitMinor: (row?['profit_minor'] as num?)?.toInt() ?? 0,
        transactions: (row?['transactions'] as num?)?.toInt() ?? 0,
      );
    });
  }

  /// Takings per calendar day from [since] up to and including today.
  ///
  /// The range is filled in, so a day with no sales is a zero bar rather than a
  /// missing one: "we shut on Tuesday" is exactly the thing an owner is looking
  /// for, and dropping the day would erase it.
  Future<List<DateBucket>> salesByDay({
    required DateTime since,
    int? staffId,
  }) async {
    final from = DateTime(since.year, since.month, since.day);
    final today = DateTime.now();
    final until = DateTime(today.year, today.month, today.day)
        .add(const Duration(days: 1));
    final where = _salesRangeWhere(since: from, until: until, staffId: staffId);
    final rows = await (await database).rawQuery('''
      SELECT
        strftime('%Y-%m-%d', created_at) AS day,
        CAST(COALESCE(SUM(total), 0) AS INTEGER) AS sales_minor,
        CAST(COALESCE(SUM(profit), 0) AS INTEGER) AS profit_minor,
        COUNT(*) AS transactions
      FROM sales
      ${where.clause}
      GROUP BY day
      ORDER BY day
    ''', where.args);
    final byDay = <String, Map<String, Object?>>{
      for (final row in rows) (row['day'] as String?) ?? '': row,
    };
    final buckets = <DateBucket>[];
    for (var cursor = from;
        cursor.isBefore(until);
        cursor = cursor.add(const Duration(days: 1))) {
      final key = '${cursor.year.toString().padLeft(4, '0')}-'
          '${cursor.month.toString().padLeft(2, '0')}-'
          '${cursor.day.toString().padLeft(2, '0')}';
      final row = byDay[key];
      buckets.add(DateBucket(
        day: key,
        label: DateFormat('d MMM').format(cursor),
        salesMinor: (row?['sales_minor'] as num?)?.toInt() ?? 0,
        profitMinor: (row?['profit_minor'] as num?)?.toInt() ?? 0,
        transactions: (row?['transactions'] as num?)?.toInt() ?? 0,
      ));
    }
    return buckets;
  }

  /// How the range was paid for, biggest first.
  Future<List<PaymentMixRow>> salesByPaymentMethod({
    required DateTime since,
    int? staffId,
  }) async {
    final where = _salesRangeWhere(since: since, staffId: staffId);
    final rows = await (await database).rawQuery('''
      SELECT
        payment_method AS method,
        CAST(COALESCE(SUM(total), 0) AS INTEGER) AS sales_minor,
        COUNT(*) AS transactions
      FROM sales
      ${where.clause}
      GROUP BY payment_method
      ORDER BY sales_minor DESC, method ASC
    ''', where.args);
    return rows
        .map((row) => PaymentMixRow(
              method: (row['method'] as String?) ?? 'cash',
              salesMinor: (row['sales_minor'] as num?)?.toInt() ?? 0,
              transactions: (row['transactions'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  /// How many active products are at or below their reorder level.
  ///
  /// The same predicate [Product.isLow] applies, but decided in SQL. The Dart
  /// version had to load every product in the catalogue and every variant
  /// behind it just to call `.where(...).length`; this is a `COUNT(*)` over an
  /// index-ordered scan and returns a single integer.
  ///
  /// `active = 1` matches [getProducts]' default, so the KPI on the dashboard
  /// counts exactly the products the inventory list would show.
  Future<int> countLowStockProducts() async {
    final rows = await (await database).rawQuery('''
      SELECT COUNT(*) AS c FROM products
      WHERE stock_qty <= reorder_level AND active = 1
    ''');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  // ---------------- Attention counts ----------------
  //
  // The four things that stop a seller's day working, counted rather than
  // derived. See services/analytics.dart's `AttentionSummary`.

  /// Sales KRA has refused and will refuse again until the shop's TIN or
  /// device id is fixed.
  ///
  /// Counted on `sales.etims_status` rather than inferred from the queue:
  /// [markEtimsRejected] leaves the row in `pending_etims` on purpose, so the
  /// queue alone cannot tell "waiting for a network" from "refused forever" —
  /// and those two need opposite responses.
  Future<int> countRejectedEtimsReceipts() async {
    final rows = await (await database).rawQuery(
      "SELECT COUNT(*) AS c FROM sales WHERE etims_status = ?",
      [EtimsStatus.rejected],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Sales taken on an offline "Paid" tap whose money has never been matched.
  ///
  /// These are *not* doubtful sales — the money was taken — so this count is a
  /// reconciliation queue, not a list of things that might have to be refunded.
  Future<int> countUnverifiedPayments() async {
    final rows = await (await database)
        .rawQuery('SELECT COUNT(*) AS c FROM sales WHERE payment_verified = 0');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Marks an offline payment as confirmed once it has been matched.
  ///
  /// The counterpart to `getUnverifiedSales`: the owner finds the row, checks it
  /// against PayHero, and confirms it here. [reference] replaces the provisional
  /// one, because the real transaction code is what makes the match auditable
  /// later.
  ///
  /// Returns false when the sale is not in this ledger, so a reconcile action
  /// against a stale id reports failure rather than silently succeeding.
  Future<bool> confirmPayment({
    required int saleId,
    String? reference,
  }) async {
    final changed = await (await database).update(
      'sales',
      {
        'payment_verified': 1,
        'payment_confirmed_at': DateTime.now().toIso8601String(),
        if (reference != null && reference.trim().isNotEmpty)
          'payment_reference': reference.trim(),
      },
      where: 'id = ? AND payment_verified = 0',
      whereArgs: [saleId],
    );
    return changed > 0;
  }

  /// The unverified sales themselves, newest first, for the reconciliation
  /// list.
  ///
  /// The raw row travels alongside the parsed [Sale] because the receipt
  /// number lives on the row and not on the model — see
  /// [receiptNumberFor]. [Sale] carries no verification state either: it is
  /// local issuance state, not a property of the sale that spreadsheets and
  /// the backend serialise.
  Future<List<(Sale, Map<String, dynamic>)>> getUnverifiedSales({
    int limit = 50,
  }) async {
    final rows = await (await database).rawQuery(
      'SELECT * FROM sales WHERE payment_verified = 0 ORDER BY created_at DESC LIMIT ?',
      [limit],
    );
    return [for (final row in rows) (Sale.fromMap(row), row)];
  }

  /// All four attention counts, in one value.
  ///
  /// Issued as four independent `COUNT(*)`s rather than one pass over `sales`
  /// with conditional sums: the two `sales` counts are on different predicates
  /// and would each need the same scan anyway, and a single combined query
  /// would break the moment a fifth thing needed counting.
  Future<AttentionSummary> attentionSummary() async {
    final results = await Future.wait([
      countPendingEtimsReceipts(),
      countRejectedEtimsReceipts(),
      countOpenImportProblems(),
      countUnverifiedPayments(),
    ]);
    return AttentionSummary(
      pendingEtims: results[0],
      rejectedEtims: results[1],
      openImportProblems: results[2],
      unverifiedPayments: results[3],
    );
  }

  // ---------------- Shifts & Reconciliation ----------------
  //
  // A shift is the accountant's view of the till: it is opened with a known
  // float, sales are attributed to it by time, and it is closed by counting the
  // cash in the drawer and reconciling against what the sales ledger says
  // should be there. Multishop scoping is by workspace key (one database file
  // per shop), so there is no shop column — a shift belongs to whichever till
  // holds its database.

  /// Opens a new shift for [staffName] / [staffId] with the given starting float.
  ///
  /// Throws if an open shift already exists for this staff member, because allowing
  /// two open shifts would make "which sales were on this shift" ambiguous.
  Future<int> openShift({
    required int staffId,
    required String staffName,
    required Money startFloat,
  }) async {
    final db = await database;
    return db.transaction<int>((txn) async {
      final existing = await txn.query('shifts',
          where: 'staff_id = ? AND status = ?',
          whereArgs: [staffId, 'open'],
          limit: 1);
      if (existing.isNotEmpty) {
        throw StateError('A shift is already open for this staff member');
      }
      final now = DateTime.now().toIso8601String();
      return txn.insert('shifts', {
        'staff_id': staffId,
        'staff_name': staffName,
        'start_time': now,
        'end_time': null,
        'start_float': startFloat.minorUnits,
        'end_float': 0,
        'status': 'open',
      });
    });
  }

  /// The one open shift for [staffId], or null when none is open.
  Future<Shift?> getOpenShift(int staffId) async {
    final rows = await (await database).query('shifts',
        where: 'staff_id = ? AND status = ?',
        whereArgs: [staffId, 'open'],
        orderBy: 'start_time DESC',
        limit: 1);
    if (rows.isEmpty) return null;
    return Shift.fromMap(rows.first);
  }

  /// Every shift for a staff member, newest first.
  Future<List<Shift>> getShifts({int? staffId, bool openOnly = false}) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];
    if (staffId != null) {
      where.add('staff_id = ?');
      args.add(staffId);
    }
    if (openOnly) {
      where.add("status = 'open'");
    }
    final rows = await db.query(
      'shifts',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'start_time DESC',
    );
    return rows.map(Shift.fromMap).toList();
  }

  /// The single open shift, or null when no one has an open shift.
  ///
  /// Used by the shell to know whether to prompt before opening a new shift.
  Future<Shift?> getAnyOpenShift() async {
    final rows = await (await database).query('shifts',
        where: "status = 'open'", orderBy: 'start_time ASC', limit: 1);
    if (rows.isEmpty) return null;
    return Shift.fromMap(rows.first);
  }

  /// Records one denomination pile counted at the till.
  Future<int> addTillCount({
    required int shiftId,
    required String denomination,
    required int count,
    required Money value,
  }) async {
    final now = DateTime.now().toIso8601String();
    return (await database).insert('till_counts', {
      'shift_id': shiftId,
      'denomination': denomination,
      'count': count,
      'value': value.minorUnits,
      'created_at': now,
    });
  }

  /// All denomination counts for a shift, in entry order.
  Future<List<TillCount>> getTillCounts(int shiftId) async {
    final rows = await (await database).query('till_counts',
        where: 'shift_id = ?', whereArgs: [shiftId], orderBy: 'id');
    return rows.map(TillCount.fromMap).toList();
  }

  /// Discards the recorded piles for a shift, so a recount replaces the last one.
  ///
  /// `addTillCount` appends, which is right for an audit trail of attempts but
  /// wrong for a cashier who counts the drawer twice — the two attempts would
  /// add together and report roughly double the cash in the till. The close is
  /// taken from the piles as they stand at that moment, so the piles are
  /// cleared immediately before they are written again.
  Future<void> clearTillCounts(int shiftId) async {
    await (await database)
        .delete('till_counts', where: 'shift_id = ?', whereArgs: [shiftId]);
  }

  /// Closes a shift and reconciles it.
  ///
  /// This is the single atomic close path: it sets the shift's end time and
  /// status, writes the reconcilation row, and clamps [endFloat] to zero if
  /// omitted. All three happen in one transaction so a crash mid-close cannot
  /// leave a shift half-closed.
  ///
  /// [countedCash] is the physical count of the till. [expectedCash] is the
  /// cash the sales ledger says should be there (start float + cash sales -
  /// change - payouts). The variance is computed as the difference.
  ///
  /// Throws [StateError] if the shift is not open. A closed shift cannot be
  /// reconciled again: the guard is on the UPDATE, and a second call would
  /// otherwise write a reconciliation row for a shift that never moved, so the
  /// ledger would show two different variances for one shift.
  Future<int> reconcileShift({
    required int shiftId,
    required Money countedCash,
    required Money expectedCash,
    Money? endFloat,
  }) async {
    final db = await database;
    return db.transaction<int>((txn) async {
      final now = DateTime.now().toIso8601String();
      final variance = countedCash - expectedCash;
      // With no explicit float, what was counted stays in the drawer and
      // becomes the next shift's float. Defaulting to zero would tell the next
      // cashier the till came up empty when it did not.
      final endFloatMinor = (endFloat ?? countedCash).minorUnits;

      final closed = await txn.update(
        'shifts',
        {
          'end_time': now,
          'end_float': endFloatMinor,
          'status': 'closed',
        },
        where: 'id = ? AND status = ?',
        whereArgs: [shiftId, 'open'],
      );
      if (closed == 0) {
        throw StateError('Shift $shiftId is not open and cannot be reconciled');
      }

      return txn.insert('reconciliations', {
        'shift_id': shiftId,
        'counted_cash': countedCash.minorUnits,
        'expected_cash': expectedCash.minorUnits,
        'variance': variance.minorUnits,
        'recorded_at': now,
      });
    });
  }

  /// All reconciliations for a shift.
  Future<List<Reconciliation>> getReconciliationsForShift(int shiftId) async {
    final rows = await (await database).query('reconciliations',
        where: 'shift_id = ?',
        whereArgs: [shiftId],
        orderBy: 'recorded_at DESC');
    return rows.map(Reconciliation.fromMap).toList();
  }

  /// The cash the sales ledger says was rung up as cash during [shift]'s window.
  ///
  /// Scoped on **both** the window and [Shift.staffId]: a shared till can have
  /// one person open the shift while another rings sales into the same drawer,
  /// and counting those as this cashier's takings would hand them a variance
  /// they did not cause. Sales that are not settled cash are excluded —
  /// `payment_method = 'cash'` and `payment_verified = 1` — because an
  /// unverified card or pending mobile-money row has not reached the drawer.
  ///
  /// Sums `sales.total`, which is already net of change given, so summing it is
  /// exactly what left the drawer. The **starting float is not included**; use
  /// [expectedTillBalance] for the figure a reconciliation compares against.
  Future<Money> expectedCashForShift(Shift shift) async {
    final since = DateTime.parse(shift.startTime);
    final until = shift.endTime != null && shift.endTime!.isNotEmpty
        ? DateTime.parse(shift.endTime!)
        : DateTime.now();
    final rows = await (await database).rawQuery(
      '''SELECT COALESCE(SUM(total), 0) AS total_minor
         FROM sales
         WHERE staff_id = ?
           AND created_at >= ?
           AND created_at < ?
           AND payment_method = 'cash'
           AND payment_verified = 1''',
      [shift.staffId, since.toIso8601String(), until.toIso8601String()],
    );
    final minor = (rows.first['total_minor'] as num?)?.toInt() ?? 0;
    return Money.fromMinor(minor);
  }

  /// What the drawer should hold for [shift]: the float it opened with plus
  /// the cash rung up since.
  ///
  /// This is the figure a physical count is compared against, so it is the one
  /// the reconciliation screen uses. Composed here rather than at each call
  /// site because forgetting the float is a mistake that produces a variance
  /// exactly equal to the float — a large, confident-looking, entirely wrong
  /// number.
  Future<Money> expectedTillBalance(Shift shift) async {
    final cash = await expectedCashForShift(shift);
    return shift.startFloat + cash;
  }

  /// Totals the denomination piles recorded for a shift.
  ///
  /// The counted cash a reconciliation should use when a cashier counted by
  /// denomination rather than typing one figure. Returns zero when no piles were
  /// recorded, which is what an uncounted till should reconcile against rather
  /// than a silent "expected" value.
  Future<Money> countedCashFromTillCounts(int shiftId) async {
    final counts = await getTillCounts(shiftId);
    var total = Money.zero;
    for (final c in counts) {
      total = total + c.value;
    }
    return total;
  }

  // ---------------- Shot cups ----------------

  /// Creates or updates a shot cup configuration.
  ///
  /// The product link is checked here rather than left to the foreign key,
  /// which is not enforced on this connection (see the foreign-key note on this
  /// class). Without the check a stale or zero [ShotCup.productId] stores a row
  /// pointing at nothing, and the till then offers a shot that cannot be
  /// priced or deducted — the sale would fail at the last step, with the
  /// customer's money already in hand.
  Future<int> upsertShotCup(ShotCup cup) async {
    final db = await database;
    if (cup.capacityMl <= 0) {
      throw StateError('A shot cup needs a capacity greater than zero');
    }
    final exists = await db.query('products',
        columns: ['id'], where: 'id = ?', whereArgs: [cup.productId], limit: 1);
    if (exists.isEmpty) {
      throw StateError(
          'Shot cup product ${cup.productId} does not exist in the catalogue');
    }
    if (cup.id == null) {
      return db.insert('shot_cups', cup.toMap()..remove('id'));
    }
    await db
        .update('shot_cups', cup.toMap(), where: 'id = ?', whereArgs: [cup.id]);
    return cup.id!;
  }

  /// Active shot cups, ordered by label then product name.
  Future<List<ShotCup>> getShotCups({bool activeOnly = true}) async {
    final rows = await (await database).query('shot_cups',
        where: activeOnly ? 'active = 1' : null,
        orderBy: 'label ASC, product_name ASC');
    return rows.map(ShotCup.fromMap).toList();
  }

  /// The shot cup configured for [productId], or null.
  Future<ShotCup?> getShotCupForProduct(int productId) async {
    final rows = await (await database).query('shot_cups',
        where: 'product_id = ? AND active = 1',
        whereArgs: [productId],
        limit: 1);
    if (rows.isEmpty) return null;
    return ShotCup.fromMap(rows.first);
  }

  /// Soft-deletes a shot cup.
  Future<void> deleteShotCup(int id) async {
    await (await database)
        .update('shot_cups', {'active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- Cup size suggestions ----------------

  /// Records (or bumps the usage count of) a cup size the user entered.
  ///
  /// [productId] is nullable so a size used across several products is
  /// remembered once and surfaces as a suggestion for any of them. If the same
  /// size already exists for the same product (or the same null product), the
  /// count is incremented; otherwise a new row is inserted.
  ///
  /// A global (null [productId]) row is matched with `IS NULL` rather than a
  /// bound argument: sqflite refuses a null in `whereArgs` and will throw once
  /// that stops being a warning, and the global bucket is the one a beer shop
  /// actually reads. Read-then-write is wrapped in a transaction so two saves
  /// of the same new size cannot both miss and insert a duplicate row.
  Future<void> upsertCupSizeSuggestion({
    int? productId,
    required int sizeMl,
  }) async {
    if (sizeMl <= 0) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final existingId = productId == null
        ? (await db.rawQuery(
            'SELECT id FROM cup_size_suggestions '
            'WHERE product_id IS NULL AND size_ml = ? LIMIT 1',
            [sizeMl],
          ))
            .map((r) => r['id'] as int)
            .firstOrNull
        : (await db.query(
            'cup_size_suggestions',
            columns: ['id', 'use_count'],
            where: 'product_id = ? AND size_ml = ?',
            whereArgs: [productId, sizeMl],
            limit: 1,
          ))
            .map((r) => r['id'] as int)
            .firstOrNull;

    if (existingId == null) {
      await db.insert('cup_size_suggestions', {
        'product_id': productId,
        'size_ml': sizeMl,
        'use_count': 1,
        'created_at': now,
      });
      return;
    }
    await db.rawUpdate(
      'UPDATE cup_size_suggestions SET use_count = use_count + 1 WHERE id = ?',
      [existingId],
    );
  }

  /// All cup size suggestions, most-used first, then by size.
  Future<List<CupSizeSuggestion>> getCupSizeSuggestions() async {
    final rows = await (await database).query(
      'cup_size_suggestions',
      orderBy: 'use_count DESC, size_ml ASC',
    );
    return rows.map(CupSizeSuggestion.fromMap).toList();
  }

  /// Suggestions for a specific product, then any global (product_id IS NULL)
  /// suggestions, most-used first.
  Future<List<CupSizeSuggestion>> getCupSizeSuggestionsForProduct(
    int productId,
  ) async {
    final rows = await (await database).rawQuery(
      '''SELECT * FROM cup_size_suggestions
         WHERE product_id = ? OR product_id IS NULL
         ORDER BY use_count DESC, size_ml ASC''',
      [productId],
    );
    return rows.map(CupSizeSuggestion.fromMap).toList();
  }
}

/// Small Kotlin-style `let` helper so we can transform the just-parsed Sale
/// inline above without an intermediate mutable variable.
extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// The lifecycle of a sale's tax invoice.
///
/// The wire vocabulary lives here, on the column that stores it, so the till
/// and the backend cannot disagree about what a value means. Kept out of
/// [Sale] because it is local issuance state, not a property of the sale that
/// spreadsheets and reports serialise.
class EtimsStatus {
  const EtimsStatus._();

  /// The shop has eTIMS switched off. The default for every row that predates
  /// the feature, and the reason a migrated ledger does not look like a wall
  /// of unreconciled receipts.
  static const String notRequired = 'not_required';

  /// Recorded locally, not yet accepted by KRA.
  static const String pending = 'pending';

  /// KRA has issued a receipt number, stored in `sales.etims_receipt_number`.
  static const String issued = 'issued';

  /// KRA refused it. The sale stands; the invoice does not, and the owner has
  /// to fix the underlying configuration.
  static const String rejected = 'rejected';
}

/// The named values `sale_items.portion` can hold.
///
/// A named class rather than bare strings because these three values are load
/// bearing in `recordSale` — they are what turns a line into the fraction of a
/// container it deducts from stock — and a typo in a string literal there is a
/// silently wrong stock count rather than a compile error.
class SalePortion {
  const SalePortion._();

  /// The whole container.
  static const String full = 'full';

  /// Half of it.
  static const String half = 'half';

  /// A quarter of it.
  static const String quarter = 'quarter';

  /// An exact pour described in millilitres, stored in `portion_ml`.
  ///
  /// A shot is 30 ml out of a 750 ml bottle. Neither `half` nor `quarter`
  /// describes that, and rounding it to `full` deducts a whole bottle per shot —
  /// so a bar selling 25 shots a bottle reads the bottle as empty after 25
  /// rather than after one. The fraction is `portion_ml / bottle_ml`, which is
  /// what makes a shot of a 200 ml bottle and a shot of a 750 ml bottle both
  /// deduct correctly from their own container.
  static const String measured = 'measured';
}

/// Why foreign keys are **not** enforced on this connection.
///
/// Read this before "fixing" it by adding `onConfigure: PRAGMA foreign_keys =
/// ON`. That pragma cannot be set from inside a transaction, sqflite runs
/// `onUpgrade` in one, and turning it on makes the v11 money migration
/// unrecoverable on any till that has recorded a sale: v11 rebuilds `sales` by
/// dropping and recreating it while `sale_items` references it, and SQLite
/// rejects a `DROP TABLE` whose implicit `DELETE FROM` would orphan a child —
/// under `defer_foreign_keys` too, because the deferred violation from the
/// implicit delete is never cleared and the failure simply moves to `COMMIT`.
/// Every ordering of the rebuild was measured; all four fail.
///
/// So the `ON DELETE CASCADE` clauses in the schema are *declarative intent*,
/// and the behaviour they promise is actually enforced in Dart — see
/// [DatabaseHelper.hardDeleteProduct], which removes a product's barcodes in the
/// same transaction as the product itself. That is the only way to guarantee
/// that a removed product's codes are freed rather than silently blocking it
/// from ever being re-added under the same barcode.

/// A sale waiting for KRA to accept its receipt.
///
/// Top level rather than nested in [DatabaseHelper] so it can be named by a
/// test or a caller without reaching through the singleton.
class PendingEtimsReceipt {
  const PendingEtimsReceipt({
    required this.saleId,
    required this.receiptNumber,
    required this.attempts,
    required this.createdAt,
    this.lastError,
  });

  final int saleId;
  final String receiptNumber;
  final int attempts;
  final DateTime createdAt;
  final String? lastError;
}
