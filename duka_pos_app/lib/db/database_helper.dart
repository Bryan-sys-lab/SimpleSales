import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/audit_log.dart';
import '../models/crash_log.dart';
import '../models/models.dart';
import '../models/stock_movement.dart';
import '../utils/crypto_utils.dart';
import '../utils/money.dart';
import '../utils/units.dart';
// The aggregate result types (DailyTotals, ProductSalesRow, TimeBucket,
// DateBucket, PaymentMixRow, AttentionSummary). They live in services/ rather
// than here so this file stays a data layer: it produces rows, it does not
// define what a chart or a screen does with them.
import '../services/analytics.dart';
import '../services/workspace_service.dart';

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

  /// Serialises moving this singleton to another shop.
  ///
  /// Held for a whole operation, not for a single switch, so that a caller
  /// which must walk several shops (the cross-shop activity read) can keep the
  /// database still for as long as it is looking.
  static final _AsyncGate _workspaceGate = _AsyncGate();

  /// Must run before the first database access. The legacy path is retained
  /// for existing installations; every additional shop gets a separate file.
  ///
  /// Takes the workspace gate (see [_AsyncGate]) so a shop switch can never
  /// land in the middle of a cross-shop tour — see
  /// [CrossShopAuditReader.readAllShops].
  Future<void> initializeWorkspace(String workspaceKey) =>
      _workspaceGate.run(() => _pointAtWorkspace(workspaceKey));

  /// Moves the database to another shop.
  ///
  /// Holds the workspace gate for the move, so it can never land in the middle
  /// of a cross-shop tour. Use [switchWorkspaceHoldingGate] from inside a tour
  /// — the gate is already held there, and taking it twice would deadlock.
  Future<void> switchWorkspace(String workspaceKey) =>
      initializeWorkspace(workspaceKey);

  /// Moves the database WITHOUT taking the workspace gate.
  ///
  /// Valid only for a caller that already holds the gate, which it obtains
  /// through [withWorkspaceGate]. A caller that switches without the gate can
  /// have its switch reverted by a concurrent tour, which leaves the till
  /// pointed at the shop the tour happened to be walking.
  Future<void> switchWorkspaceHoldingGate(String workspaceKey) =>
      _pointAtWorkspace(workspaceKey);

  Future<void> _pointAtWorkspace(String workspaceKey) async {
    if (workspaceKey.trim().isEmpty) {
      throw ArgumentError.value(workspaceKey, 'workspaceKey');
    }
    if (_db != null && _workspaceKey == workspaceKey) return;
    await _db?.close();
    _db = null;
    _workspaceKey = workspaceKey;
  }

  /// Runs [body] holding the workspace gate.
  ///
  /// The gate exists because the whole process reads and writes through this
  /// one singleton: while a body holds it, no other code can move the database
  /// to another shop, and the gate is what makes a multi-shop tour safe to run
  /// from a screen the rest of the app is still using.
  Future<T> withWorkspaceGate<T>(Future<T> Function() body) =>
      _workspaceGate.run(body);

  /// The shop this singleton is CURRENTLY pointed at.
  ///
  /// Distinct from `WorkspaceService.activeWorkspaceKey()`, and deliberately so:
  /// the registry in SharedPreferences is what a *user* chose, while this is
  /// what the *database* is actually reading. A cross-shop reader that restores
  /// from the registry would restore the user's choice even though it had
  /// already moved the database somewhere else — and would then point the till
  /// at a shop whose stock it is not showing.
  ///
  /// A caller that walked several shops and wants to put things back exactly as
  /// they found them needs THIS.
  String get currentWorkspaceKey => _workspaceKey;

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
  static const _schemaVersion = 29;

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

  /// The file path a workspace's database lives at, computed the same way
  /// `_initDb` computes it — so a cross-shop reader can open its own read-only
  /// handle instead of repointing this process-global singleton.
  static Future<String> databasePathFor(String workspaceKey) async {
    final dbPath = await getDatabasesPath();
    final safeKey = workspaceKey.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return workspaceKey == 'legacy'
        ? join(dbPath, 'duka_pos.db')
        : join(dbPath, 'duka_pos_$safeKey.db');
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
    if (oldVersion < 16) {
      final staffCols16 = await db.rawQuery('PRAGMA table_info(staff)');
      final staffNames16 = staffCols16.map((r) => r['name'] as String?).toSet();
      if (!staffNames16.contains('username')) {
        await db.execute('ALTER TABLE staff ADD COLUMN username TEXT');
      }
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_username ON staff (username) WHERE username IS NOT NULL');
    }
    if (oldVersion < 17) {
      // Indexes for query hotspots the v10 set did not cover. Without these,
      // a shop with months of history full-scans `sales` on every dashboard
      // load and product load.
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sales_payment_verified ON sales (payment_verified, created_at DESC)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sales_etims_status ON sales (etims_status)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_active ON products (active)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_products_track_variants ON products (track_variants)');
    }
    if (oldVersion < 18) {
      // Who did what, when. The ledger records that a sale happened and a
      // stock adjustment happened; neither says which manager changed the VAT
      // rate at 11pm, or which cashier erased a backup. Every state-changing
      // action in the app writes one row here.
      //
      // The table and its indexes live in [_createAuditLogTable] so `onCreate`
      // and this upgrade path run the SAME code and the two schemas cannot
      // diverge. `migration_test.dart` asserts that invariant directly.
      await _createAuditLogTable(db);
    }
    if (oldVersion < 19) {
      // What went wrong, and what the app was doing when it did. The other half
      // of the audit log, for the moments no action commit succeeded.
      //
      // Bounded and self-deleting: the recorder trims on every write, so a
      // phone that crashes repeatedly cannot fill its storage before anybody
      // reads it.
      await _createCrashLogTable(db);
    }
    if (oldVersion < 20) {
      // The product's photograph, held as a RELATIVE path.
      //
      // The bytes live in `product_photos/<id>.jpg` under the app's documents
      // directory; only the path is in the row. A photograph is the one large
      // thing on a product — storing the bytes would put them in every
      // encrypted backup and every cross-shop read, against a few dozen bytes
      // for the rest of the row.
      //
      // Relative so it survives a migration: the absolute directory differs
      // between phones, and an absolute path restored onto a different handset
      // would point at a folder that does not exist there.
      await db.execute('ALTER TABLE products ADD COLUMN image_path TEXT');
    }
    if (oldVersion < 21) {
      // The header-to-field mapping the import that refused the row used.
      //
      // A problem row stores the raw cells only, and those cells mean nothing
      // without the mapping: re-reading them against the canonical order puts
      // a selling price in the cost field of the review form. Nullable because
      // rows recorded before it — and rows from any other writer — fall back to
      // the canonical order.
      //
      // THREE lines of defence, because this block runs on every version below
      // 21 and they do not all arrive at the same shape:
      //
      //   * CREATE IF NOT EXISTS first, so a database that never had the table —
      //     a fixture, or a till whose own migrations were interrupted — gets it
      //     rather than aborting the ALTER with "no such table".
      //   * The ALTER is then guarded by PRAGMA, because a v13 shop runs the
      //     `<14` block, whose `_createVariantsAndImportTables` creates the
      //     table WITH this column: a bare ADD COLUMN there is a duplicate
      //     column name, which throws out of `_onUpgrade` and out of
      //     `openDatabase` — an upgraded till that cannot open its database at
      //     all, which is the failure these migrations exist to prevent.
      //   * Version alone decides nothing; the shape on disk does.
      await _createImportNeedsAttentionTable(db);
      final columns =
          await db.rawQuery('PRAGMA table_info(import_needs_attention)');
      if (!columns.any((row) => row['name'] == 'column_map')) {
        await db.execute(
            'ALTER TABLE import_needs_attention ADD COLUMN column_map TEXT');
      }
    }
    if (oldVersion < 22) {
      // How many millilitres one kilogram of the product is.
      //
      // A tank of beer is stocked by WEIGHT — the number on the delivery note
      // and on the scale — and sold by the cup, which is millilitres. This is
      // the bridge: `kg x this` is the volume the app counts and pours, and
      // [Product.millilitresPerKilogram] carries the per-product factor because
      // not everything that arrives by weight holds a litre per kilogram.
      //
      // Defaults to 0, which is the field's way of saying "not stocked by
      // weight" — every existing row answers 0 and stays a volume product, so
      // nothing about the shop's current catalogue changes shape on upgrade.
      final productColumns = await db.rawQuery('PRAGMA table_info(products)');
      if (!productColumns.any((row) => row['name'] == 'ml_per_kg')) {
        await db.execute(
            'ALTER TABLE products ADD COLUMN ml_per_kg REAL NOT NULL DEFAULT 0');
      }
    }
    if (oldVersion < 23) {
      // Repair migration: till(s) that reached v12 from the v12 helper got
      // different column declarations than _onCreate (owner lost name/email,
      // staff lost active/remote_id/username, stock_adjustments never existed).
      // Add anything missing rather than assuming the shape on disk.
      // Only tables that exist are touched; a till whose upgrade path never
      // created one of these tables is left alone.
      // owner
      final ownerExists = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='owner'");
      if (ownerExists.isNotEmpty) {
        final ownerCols = await db.rawQuery('PRAGMA table_info(owner)');
        final ownerNames = ownerCols.map((r) => r['name'] as String?).toSet();
        if (!ownerNames.contains('name')) {
          await db.execute(
              'ALTER TABLE owner ADD COLUMN name TEXT NOT NULL DEFAULT \'\'');
        }
        if (!ownerNames.contains('email')) {
          await db.execute(
              'ALTER TABLE owner ADD COLUMN email TEXT NOT NULL DEFAULT \'\'');
        }
      }
      // staff
      final staffExists = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='staff'");
      if (staffExists.isNotEmpty) {
        final staffCols = await db.rawQuery('PRAGMA table_info(staff)');
        final staffNames = staffCols.map((r) => r['name'] as String?).toSet();
        if (!staffNames.contains('active')) {
          await db.execute(
              'ALTER TABLE staff ADD COLUMN active INTEGER NOT NULL DEFAULT 1');
          // Backfill from the legacy is_active column left by the drifted
          // v12 helper, so deactivated staff stay deactivated after the
          // repair. The DEFAULT 1 above is overwritten per-row here.
          if (staffNames.contains('is_active')) {
            await db.execute('UPDATE staff SET active = is_active');
          }
        }
        if (!staffNames.contains('remote_id')) {
          await db.execute('ALTER TABLE staff ADD COLUMN remote_id TEXT');
        }
        if (!staffNames.contains('username')) {
          await db.execute('ALTER TABLE staff ADD COLUMN username TEXT');
        }
      }
      // stock_adjustments may not exist at all on an upgraded till.
      final stockAdjExists = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='stock_adjustments'");
      if (stockAdjExists.isEmpty) {
        await db.execute('''CREATE TABLE IF NOT EXISTS stock_adjustments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          product_name TEXT NOT NULL,
          delta INTEGER NOT NULL,
          reason TEXT,
          staff_name TEXT NOT NULL,
          staff_id INTEGER,
          created_at TEXT NOT NULL
        )''');
      } else {
        final adjCols =
            await db.rawQuery('PRAGMA table_info(stock_adjustments)');
        final adjNames = adjCols.map((r) => r['name'] as String?).toSet();
        if (!adjNames.contains('product_name')) {
          await db.execute(
              'ALTER TABLE stock_adjustments ADD COLUMN product_name TEXT NOT NULL DEFAULT \'\'');
        }
        if (!adjNames.contains('staff_name')) {
          await db.execute(
              'ALTER TABLE stock_adjustments ADD COLUMN staff_name TEXT NOT NULL DEFAULT \'\'');
        }
        if (!adjNames.contains('staff_id')) {
          await db.execute(
              'ALTER TABLE stock_adjustments ADD COLUMN staff_id INTEGER');
        }
      }
      // sales: the VAT rate in force when the sale was rung, so reprints,
      // reports and eTIMS uploads of old sales use the rate that applied then.
      final salesExists = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='sales'");
      if (salesExists.isNotEmpty) {
        final salesCols = await db.rawQuery('PRAGMA table_info(sales)');
        final salesNames = salesCols.map((r) => r['name'] as String?).toSet();
        if (!salesNames.contains('vat_rate_percent')) {
          await db
              .execute('ALTER TABLE sales ADD COLUMN vat_rate_percent INTEGER');
        }
      }
    }
    if (oldVersion < 24) await _migrateEtimsQrPayload(db);
    if (oldVersion < 25) await _repairEtimsQrPayloadColumn(db);
    if (oldVersion < 26) await _migrateFoundation(db);
    if (oldVersion < 27) await _migrateTillSyncFlags(db);
    if (oldVersion < 28) await _migrateReturns(db);
    if (oldVersion < 29) await _migrateReceipts(db);
  }

  // ---------------- Receiving stock, and what it cost (v29) ----------------

  /// The tables a delivery is written to.
  ///
  /// Additive only. A till that upgrades has stock on it that was bought at
  /// a price, and none of this touches it: the cost history starts with the
  /// delivery that comes next, and the products keep the cost they had.
  Future<void> _migrateReceipts(Database db) async {
    await _createReceiptTables(db);
  }

  /// The tables a delivery is written to — ONE definition, used by the
  /// migration and by a fresh install.
  ///
  /// ## WHY THERE IS A SUPPLIER TABLE
  ///
  /// A shop buys from a handful of people, and the purchase history is worth
  /// much more when it says WHO. A supplier is soft-deleted rather than
  /// removed, because a receipt from a supplier who has gone is still a fact
  /// about the stock.
  ///
  /// ## WHY THERE IS A COST HISTORY
  ///
  /// "Today cost is a static field, so profit drifts from reality." The cost
  /// on the product is the cost as it stands; the history is how it got there.
  /// Without it, a price that moved in March cannot be told from one that
  /// moved last Tuesday, and the profit on the stock bought in between is a
  /// guess.
  Future<void> _createReceiptTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        contact_person TEXT,
        notes TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_suppliers_name ON suppliers (name)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER,
        supplier_ref TEXT,
        received_at TEXT NOT NULL,
        staff_id INTEGER,
        staff_name TEXT NOT NULL,
        total_cost_minor INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'posted',
        note TEXT,
        synced_to_backend INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_receipt_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        variant_id INTEGER,
        product_name TEXT NOT NULL,
        qty REAL NOT NULL,
        unit_cost_minor INTEGER NOT NULL DEFAULT 0,
        line_cost_minor INTEGER NOT NULL DEFAULT 0,
        old_cost_minor INTEGER,
        new_cost_minor INTEGER,
        FOREIGN KEY (receipt_id) REFERENCES stock_receipts (id) ON DELETE CASCADE
      )
    ''');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_stock_receipt_items_receipt '
            'ON stock_receipt_items (receipt_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_cost_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        variant_id INTEGER,
        effective_at TEXT NOT NULL,
        old_cost_minor INTEGER NOT NULL DEFAULT 0,
        new_cost_minor INTEGER NOT NULL DEFAULT 0,
        reason TEXT NOT NULL DEFAULT 'receipt',
        receipt_id INTEGER
      )
    ''');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_product_cost_history_product '
            'ON product_cost_history (product_id, effective_at)');
  }

  // ---------------- Returns and credit notes (v28) ----------------

  /// The tables a return is written to.
  ///
  /// Additive only, and additive for a reason: a till that upgrades has sales
  /// on it that have already been returned against by hand, and nothing here
  /// touches those.
  ///
  /// The LINES carry a copy of the sale line's name, price and tax rate, and
  /// the refund figure itself. A return is a historical document: it says what
  /// the goods were worth ON THE DAY THEY WERE SOLD, because the price on the
  /// shelf today is not the money that went back.
  Future<void> _migrateReturns(Database db) async {
    await _createReturnTables(db);
  }

  /// The tables a return is written to.
  ///
  /// ONE definition, used by both paths: the migration for a till that
  /// upgrades, and the fresh install for a till that does not. Two copies of
  /// a CREATE TABLE is two places for them to disagree.
  Future<void> _createReturnTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        kind TEXT NOT NULL DEFAULT 'refund',
        reason TEXT NOT NULL,
        total INTEGER NOT NULL DEFAULT 0,
        vat_total INTEGER NOT NULL DEFAULT 0,
        profit INTEGER NOT NULL DEFAULT 0,
        refund_method TEXT NOT NULL DEFAULT 'cash',
        payment_reference TEXT,
        -- The drawer the money left, for a cash refund. The shift that was
        -- OPEN at the time of the return, not the one the sale was rung in.
        shift_id INTEGER,
        staff_id INTEGER,
        staff_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        synced_to_backend INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_returns_sale ON sale_returns (sale_id)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_return_items (
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
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_return_items_return ON sale_return_items (return_id)');
  }

  // ---------------- The till's records, and their push (v27) ----------------

  /// Marks the records that have reached the server.
  ///
  /// The till writes its ledger, its drawers and its shot cups OFFLINE, and
  /// pushes them when the phone can reach the server. A phone that was
  /// offline pushes the same records again — that is the whole mechanism — so
  /// the app has to know which ones the server already has, or a week's
  /// takings become two weeks of takings the moment the signal comes back.
  ///
  /// A FLAG, not a deletion: the record is the shop's own history and it stays
  /// on the phone whether the server has seen it or not. What the flag says is
  /// "the server has this one", and only the push reads it.
  Future<void> _migrateTillSyncFlags(Database db) async {
    for (final String table in <String>['sales', 'shifts', 'shot_cups']) {
      // Only a table that IS THERE.
      //
      // A migration runs against whatever the phone has, and a phone whose
      // database predates the shifts table — or a hand-made copy of one — must
      // not be brought to its knees by an ALTER against a table that was never
      // created. A table that does not exist yet is created by the migration
      // that owns it, and that one has the column in its CREATE.
      final List<Map<String, Object?>> tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        <Object?>[table],
      );
      if (tables.isEmpty) continue;
      final List<Map<String, Object?>> columns =
          await db.rawQuery('PRAGMA table_info($table)');
      final bool alreadyThere = columns.any(
        (Map<String, Object?> column) => column['name'] == 'synced_to_backend',
      );
      if (!alreadyThere) {
        await db.execute(
          'ALTER TABLE $table ADD COLUMN synced_to_backend INTEGER NOT NULL DEFAULT 0',
        );
      }
    }
  }

  // ---------------- Foundation: ledger, payments, tax (v26) ----------------

  /// The three foundations, as one migration.
  ///
  /// They ship together because they are one idea seen from three sides: a
  /// sale is a document with lines, a payment and a tax figure, and every
  /// change to stock is a row that says who moved it and why. Splitting them
  /// would mean touching the same tables three times and migrating the same
  /// shop's data three times.
  ///
  /// The DDL lives in [_createFoundationTables] so a fresh install and an
  /// upgraded one cannot diverge — the exact defect the v24 step introduced
  /// and the v25 step had to repair.
  Future<void> _migrateFoundation(Database db) async {
    await _createFoundationTables(db);
    await _backfillOpeningStockMovements(db);
    await _backfillHistoricAdjustments(db);
    await _backfillSalePayments(db);
    await _backfillTaxSnapshots(db);
  }

  /// The ledger, the payment table and the tax columns.
  ///
  /// Additive only. Nothing is dropped or rewritten, so the columns the old
  /// code writes are still there for the two releases the spec allows, and a
  /// downgrade still opens the database.
  Future<void> _createFoundationTables(Database db) async {
    // Every stock change becomes an immutable, attributable row.
    //
    // The product's own `stock_qty` stays as a cached balance, updated in the
    // same transaction as the movement that caused it. Two copies of the
    // truth, one of them derived — which is why there is a check that says
    // when they disagree.
    //
    // `uuid` is there from day one, not added when multi-device sync arrives:
    // a stable identity cannot be backfilled onto a table that already has
    // rows, because two of them would have to be given the same value.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        product_id INTEGER NOT NULL,
        variant_id INTEGER,
        movement_type TEXT NOT NULL,
        qty_delta REAL NOT NULL,
        unit_cost_minor INTEGER,
        reference_type TEXT,
        reference_id INTEGER,
        batch_id INTEGER,
        staff_id INTEGER,
        staff_name TEXT,
        note TEXT,
        balance_after REAL NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements (product_id, created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_variant ON stock_movements (variant_id, created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_reference ON stock_movements (reference_type, reference_id)');

    // One sale can be paid in several parts. The sale's own `payment_method`
    // stays as a summary for the code that reads it today.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_payments (
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
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_payments_sale ON sale_payments (sale_id)');

    await _addColumnIfMissing(
        db, 'products', 'tax_class', "TEXT NOT NULL DEFAULT 'standard'");
    await _addColumnIfMissing(db, 'sale_items', 'tax_class', 'TEXT');
    await _addColumnIfMissing(db, 'sale_items', 'vat_rate_bps', 'INTEGER');
    await _addColumnIfMissing(db, 'sale_items', 'vat_minor', 'INTEGER');
    await _addColumnIfMissing(db, 'sale_items', 'taxable_minor', 'INTEGER');
    await _addColumnIfMissing(db, 'sales', 'vat_minor', 'INTEGER');
    await _addColumnIfMissing(db, 'sales', 'taxable_minor', 'INTEGER');
    await _addColumnIfMissing(
        db, 'sales', 'document_type', "TEXT NOT NULL DEFAULT 'sale'");
    // A legacy sale's VAT was backfilled, not computed from what was on the
    // invoice. The flag says so, so a report can note it rather than present
    // a guess as a measurement.
    await _addColumnIfMissing(
        db, 'sales', 'vat_estimated', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'pending_etims', 'document_type', "TEXT NOT NULL DEFAULT 'sale'");
    await _addColumnIfMissing(db, 'pending_etims', 'return_id', 'INTEGER');
  }

  /// Adds a column when the table is there and the column is not.
  ///
  /// Guarded, so the same helper serves a fresh install, an upgrade from any
  /// older schema, and a schema that has already diverged — which is the only
  /// way one DDL definition can be applied twice without a "duplicate column
  /// name" on every fresh install.
  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
        [table]);
    if (exists.isEmpty) return;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final names = columns.map((r) => r['name'] as String?).toSet();
    if (names.contains(column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  /// The columns a table actually has.
  ///
  /// A migration reads tables that older code built, and older code built
  /// some of them differently — a `stock_adjustments` without an `id`, a
  /// `products` without `track_variants`. The backfills read what is there
  /// rather than what they expect, because a migration that fails halfway
  /// leaves a shop that cannot open its till.
  Future<Set<String>> _columnsOf(Database db, String table) async {
    final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
        [table]);
    if (exists.isEmpty) return const <String>{};
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    return columns.map((r) => r['name'] as String?).whereType<String>().toSet();
  }

  /// The opening balance of every product and every variant.
  ///
  /// A ledger that starts from nothing cannot be checked: every product's
  /// balance would read as "wrong" because the history that made it is not
  /// there. So the migration writes one opening movement per product and per
  /// variant, equal to the count the shop has today, dated now.
  ///
  /// Written in batches so a shop with ten thousand products does not build
  /// ten thousand rows in memory at once.
  Future<void> _backfillOpeningStockMovements(Database db) async {
    const int batchSize = 1000;
    final now = DateTime.now().toIso8601String();
    final productColumns = await _columnsOf(db, 'products');
    if (productColumns.isEmpty) return;
    final variantColumns = await _columnsOf(db, 'product_variants');
    // A database old enough not to track variants has no variants, and one
    // old enough to have them without the flag treats every product as
    // untracked.
    final bool tracksVariants = productColumns.contains('track_variants');
    final bool variantsHaveActive = variantColumns.contains('active');

    // A product that is sold as variants holds an AGGREGATE, so its own count
    // is the sum of its variants' counts and must not be opened a second time.
    // The variant movements are the real ones; the parent's opening row is
    // what makes the parent's count traceable to the ledger as well.
    final products = await db.rawQuery('''
      SELECT id, stock_qty, name FROM products
      WHERE ${tracksVariants ? 'COALESCE(track_variants, 0) = 0' : '1 = 1'}
      ORDER BY id
    ''');
    for (var offset = 0; offset < products.length; offset += batchSize) {
      final end = (offset + batchSize > products.length)
          ? products.length
          : offset + batchSize;
      for (final row in products.sublist(offset, end)) {
        final double balance = (row['stock_qty'] as num?)?.toDouble() ?? 0;
        await db.insert('stock_movements', {
          'uuid': _newUuid(),
          'created_at': now,
          'product_id': row['id'],
          'variant_id': null,
          'movement_type': StockMovementType.opening.wire,
          'qty_delta': balance,
          'unit_cost_minor': null,
          'reference_type': null,
          'reference_id': null,
          'batch_id': null,
          'staff_id': null,
          'staff_name': null,
          'note': 'Opening balance',
          'balance_after': balance,
        });
      }
    }

    if (variantColumns.isEmpty) return;

    final variants = await db.rawQuery('''
      SELECT v.id, v.product_id, v.stock_qty FROM product_variants v
      JOIN products p ON p.id = v.product_id
      WHERE ${tracksVariants ? 'COALESCE(p.track_variants, 0) = 1' : '1 = 1'}
      ORDER BY v.id
    ''');
    for (var offset = 0; offset < variants.length; offset += batchSize) {
      final end = (offset + batchSize > variants.length)
          ? variants.length
          : offset + batchSize;
      for (final row in variants.sublist(offset, end)) {
        final double balance = (row['stock_qty'] as num?)?.toDouble() ?? 0;
        await db.insert('stock_movements', {
          'uuid': _newUuid(),
          'created_at': now,
          'product_id': row['product_id'],
          'variant_id': row['id'],
          'movement_type': StockMovementType.opening.wire,
          'qty_delta': balance,
          'unit_cost_minor': null,
          'reference_type': null,
          'reference_id': null,
          'batch_id': null,
          'staff_id': null,
          'staff_name': null,
          'note': 'Opening balance',
          'balance_after': balance,
        });
      }
    }

    // A product sold as variants still needs a parent row, because the
    // parent's count is the aggregate and the ledger has to be able to check
    // it. Its opening movement is the aggregate at the moment of the
    // migration.
    if (!tracksVariants) return;
    final tracked = await db.rawQuery('''
      SELECT p.id,
             (SELECT COALESCE(SUM(v.stock_qty), 0) FROM product_variants v
              WHERE v.product_id = p.id ${variantsHaveActive ? 'AND v.active = 1' : ''}) AS aggregate
        FROM products p
       WHERE COALESCE(p.track_variants, 0) = 1
       ORDER BY p.id
    ''');
    for (var offset = 0; offset < tracked.length; offset += batchSize) {
      final end = (offset + batchSize > tracked.length)
          ? tracked.length
          : offset + batchSize;
      for (final row in tracked.sublist(offset, end)) {
        final double balance = (row['aggregate'] as num?)?.toDouble() ?? 0;
        await db.insert('stock_movements', {
          'uuid': _newUuid(),
          'created_at': now,
          'product_id': row['id'],
          'variant_id': null,
          'movement_type': StockMovementType.opening.wire,
          'qty_delta': balance,
          'unit_cost_minor': null,
          'reference_type': null,
          'reference_id': null,
          'batch_id': null,
          'staff_id': null,
          'staff_name': null,
          'note': 'Opening balance',
          'balance_after': balance,
        });
      }
    }
  }

  /// The stock adjustments the shop already made, as ledger rows.
  ///
  /// The old table stays for two releases — the app still writes it — but the
  /// ledger needs the history, and the history is here. Only the adjustments
  /// whose date and amount are known are copied: an adjustment with no date
  /// cannot be placed in a ledger that is ordered by time.
  Future<void> _backfillHistoricAdjustments(Database db) async {
    final columns = await _columnsOf(db, 'stock_adjustments');
    if (columns.isEmpty) return;
    if (!columns.contains('delta') ||
        !columns.contains('created_at') ||
        !columns.contains('product_id')) {
      return;
    }
    // `rowid` stands in for a missing `id`: every SQLite table has one, and
    // the order it gives is the order the rows were written in.
    final String orderColumn = columns.contains('id') ? 'id' : 'rowid';
    final rows = await db.rawQuery('''
      SELECT product_id, delta, created_at,
             ${columns.contains('staff_id') ? 'staff_id' : 'NULL AS staff_id'},
             ${columns.contains('staff_name') ? 'staff_name' : 'NULL AS staff_name'},
             ${columns.contains('reason') ? 'reason' : 'NULL AS reason'}
        FROM stock_adjustments
       WHERE created_at IS NOT NULL AND delta IS NOT NULL
       ORDER BY $orderColumn
    ''');
    for (final row in rows) {
      final int productId = row['product_id'] as int;
      final double delta = (row['delta'] as num).toDouble();
      final double balance = await _stockBalanceAfter(db, productId, delta);
      await db.insert('stock_movements', {
        'uuid': _newUuid(),
        'created_at': row['created_at'] as String,
        'product_id': productId,
        'variant_id': null,
        'movement_type': StockMovementType.adjustment.wire,
        'qty_delta': delta,
        'unit_cost_minor': null,
        'reference_type': 'adjustment',
        'reference_id': null,
        'staff_id': row['staff_id'] as int?,
        'staff_name': row['staff_name'] as String?,
        'note': row['reason'] as String?,
        'balance_after': balance,
      });
    }
  }

  /// The balance a product would have after [delta], read from the ledger.
  ///
  /// Used while backfilling history, where the rows are written in the order
  /// they happened and each one carries the balance at that moment — the
  /// `balance_after` column is what makes a ledger readable without summing
  /// it.
  Future<double> _stockBalanceAfter(
    Database db,
    int productId,
    double delta,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(qty_delta), 0) AS total FROM stock_movements '
      'WHERE product_id = ? AND variant_id IS NULL',
      [productId],
    );
    final double current = (rows.first['total'] as num?)?.toDouble() ?? 0;
    return current + delta;
  }

  /// One payment row per sale that already exists.
  ///
  /// The sale's own summary method becomes a single confirmed payment, with
  /// the tendered amount and the change it produced. A sale paid by M-Pesa
  /// that was never confirmed keeps that fact: the payment is `unverified`, so
  /// the reconciliation queue can still find it.
  Future<void> _backfillSalePayments(Database db) async {
    const int batchSize = 1000;
    final columns = await _columnsOf(db, 'sales');
    if (columns.isEmpty) return;
    // A sales table old enough not to have the tendered amount or the
    // verification flag still has a payment, and it is the method and the
    // total that say what it was.
    String column(String name, String fallback) =>
        columns.contains(name) ? name : fallback;
    final rows = await db.rawQuery('''
      SELECT id,
             ${column('payment_method', "'cash' AS payment_method")},
             ${column('payment_reference', 'NULL AS payment_reference')},
             ${column('amount_tendered', '0 AS amount_tendered')},
             ${column('change_given', '0 AS change_given')},
             ${column('payment_verified', '1 AS payment_verified')},
             created_at
        FROM sales
       ORDER BY id
    ''');
    for (var offset = 0; offset < rows.length; offset += batchSize) {
      final end =
          (offset + batchSize > rows.length) ? rows.length : offset + batchSize;
      for (final row in rows.sublist(offset, end)) {
        final int saleId = row['id'] as int;
        final bool exists = await _hasPaymentFor(db, saleId);
        if (exists) continue;
        // The amounts are numbers, not necessarily integers: a database older
        // than the money migration stored them as REAL. The payment table
        // holds minor units, so they are read as numbers and rounded once,
        // here.
        final int tendered = (row['amount_tendered'] as num?)?.toInt() ?? 0;
        final int change = (row['change_given'] as num?)?.toInt() ?? 0;
        final bool verified =
            ((row['payment_verified'] as num?)?.toInt() ?? 1) == 1;
        await db.insert('sale_payments', {
          'uuid': _newUuid(),
          'sale_id': saleId,
          'method': row['payment_method'] as String? ?? 'cash',
          'amount_minor': tendered - change,
          'tendered_minor': tendered,
          'change_minor': change,
          'reference': row['payment_reference'] as String?,
          'status': verified ? 'confirmed' : 'unverified',
          'pending_payment_id': null,
          'created_at': row['created_at'] as String,
        });
      }
    }
  }

  Future<bool> _hasPaymentFor(Database db, int saleId) async {
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM sale_payments WHERE sale_id = ?', [saleId]);
    return ((rows.first['c'] as int?) ?? 0) > 0;
  }

  /// The VAT on the sales that predate the tax columns.
  ///
  /// Backfilled with the shop's VAT rate at the time of the migration, and
  /// marked as estimated: the figure was never on the receipt, so a report
  /// that shows it must say where it came from. A sale's own stored rate is
  /// used when it has one, because a shop that changed its rate changed it for
  /// a reason.
  Future<void> _backfillTaxSnapshots(Database db) async {
    const int batchSize = 1000;
    final rate = await _shopVatRatePercent(db);
    final columns = await _columnsOf(db, 'sales');
    if (columns.isEmpty) return;
    final rows = await db.rawQuery('''
      SELECT id, total,
             ${columns.contains('vat_rate_percent') ? 'vat_rate_percent' : 'NULL AS vat_rate_percent'}
        FROM sales
       WHERE vat_minor IS NULL
       ORDER BY id
    ''');
    for (var offset = 0; offset < rows.length; offset += batchSize) {
      final end =
          (offset + batchSize > rows.length) ? rows.length : offset + batchSize;
      for (final row in rows.sublist(offset, end)) {
        final int saleId = row['id'] as int;
        final int total = (row['total'] as num?)?.toInt() ?? 0;
        final int saleRate = (row['vat_rate_percent'] as num?)?.toInt() ?? rate;
        final int vat = _vatFromInclusive(total, saleRate);
        await db.update(
          'sales',
          {
            'vat_minor': vat,
            'taxable_minor': total - vat,
            'vat_estimated': 1,
          },
          where: 'id = ?',
          whereArgs: [saleId],
        );
      }
    }
  }

  /// The shop's VAT rate, in percent.
  ///
  /// The shop's own setting, read the same way the rest of the app reads it.
  /// A database old enough not to have the settings table yet has no rate
  /// either, so the statutory default stands in.
  Future<int> _shopVatRatePercent(Database db) async {
    final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = 'shop_settings'");
    if (exists.isEmpty) return 16;
    final rows = await db.query('shop_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['vat_rate_percent'],
        limit: 1);
    if (rows.isEmpty) return 16;
    return int.tryParse(rows.first['value'] as String? ?? '') ?? 16;
  }

  /// The VAT contained in a VAT-inclusive amount.
  ///
  /// The same rule the receipt prints and the eTIMS payload sends, so the
  /// figure in the ledger, on the paper and with KRA are the same cent.
  static int _vatFromInclusive(int amountMinor, int ratePercent) {
    if (amountMinor <= 0 || ratePercent <= 0) return 0;
    // amount = net * (1 + rate)  =>  vat = amount - amount / (1 + rate)
    final int net = (amountMinor * 100) ~/ (100 + ratePercent);
    return amountMinor - net;
  }

  /// A fresh identity for a ledger row.
  ///
  /// A UUID v4, so two tills that make the same movement never mint the same
  /// one and a synchronised row can be recognised as the same row.
  static String _newUuid() => generateUuid();

  /// v25: repair the one column a fresh install never had.
  ///
  /// `sales.etims_qr_payload` was introduced by the v24 step, which only runs
  /// on an UPGRADE. A till that was installed fresh while the app was already
  /// at v24 therefore never received it — the v24 step was skipped, because
  /// there was nothing to upgrade from. On such a till every KRA receipt
  /// resolution failed with "no such column: etims_qr_payload", so no receipt
  /// was ever issued and no QR was ever printed.
  ///
  /// The column is now also added by [_createEtimsTables], which runs on every
  /// fresh install, so this step only has to catch the tills that were
  /// installed during the window when it was missing.
  ///
  /// The v24 step does the work: it is idempotent — it adds the column only
  /// when it is missing, and its backfill only touches receipts that have no
  /// payload yet — so one code path serves both the upgrade and the repair.
  Future<void> _repairEtimsQrPayloadColumn(Database db) async {
    await _migrateEtimsQrPayload(db);
  }

  /// Adds `sales.etims_qr_payload` when the column is not already there.
  ///
  /// Guarded, so it is safe to call from the fresh-install path, from the v13
  /// upgrade and from the v24 step: whichever runs first adds the column and
  /// the others see it and do nothing.
  Future<void> _ensureEtimsQrPayloadColumn(Database db) async {
    final salesExists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sales'");
    if (salesExists.isEmpty) return;
    final salesCols = await db.rawQuery('PRAGMA table_info(sales)');
    final salesNames = salesCols.map((r) => r['name'] as String?).toSet();
    if (salesNames.contains('etims_qr_payload')) return;
    await db.execute('ALTER TABLE sales ADD COLUMN etims_qr_payload TEXT');
  }

  /// v24: persist KRA's own `qr_payload` on the sale so reprints scan to the
  /// real verification page instead of a locally built URL.
  ///
  /// Added defensively with a `PRAGMA table_info` check so a till that already
  /// carries the column (or a schema that diverged) does not throw.
  Future<void> _migrateEtimsQrPayload(Database db) async {
    await _ensureEtimsQrPayloadColumn(db);
    final salesExists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sales'");
    if (salesExists.isEmpty) return;
    final salesCols = await db.rawQuery('PRAGMA table_info(sales)');
    final salesNames = salesCols.map((r) => r['name'] as String?).toSet();
    // Backfill: for receipts issued before v24, rebuild the old-style
    // verification URL from the receipt number so reprints still carry a
    // scannable QR code. New receipts get KRA's own qr_payload directly.
    // etims_receipt_number only exists on newer schemas; skip the backfill
    // on legacy databases where that column was never added.
    if (!salesNames.contains('etims_receipt_number')) return;
    const backendUrl = String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'https://localhost:3000/api',
    );
    final base = backendUrl.replaceAll(RegExp(r'/+$'), '');
    if (base.isNotEmpty) {
      await db.rawUpdate(
        "UPDATE sales SET etims_qr_payload = ? || '/etims/verify/' || "
        "TRIM(etims_receipt_number) "
        "WHERE etims_qr_payload IS NULL "
        "AND etims_receipt_number IS NOT NULL "
        "AND TRIM(etims_receipt_number) != '' "
        "AND etims_status = ?",
        [base, EtimsStatus.issued],
      );
    }
  }

  /// The import rows a shop still owes an answer, and their open-count index.
  ///
  /// ONE definition, called from `_onCreate`, from the `<14` migration that
  /// introduced the table, and from the v21 step that extended it — so the
  /// three paths cannot describe the same table differently.
  Future<void> _createImportNeedsAttentionTable(Database db) async {
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

  /// v19: the failure log — what broke, and what the shop was doing.
  ///
  /// Called from BOTH paths, for the same reason as [_createAuditLogTable]: a
  /// shop must not get a different database depending on when it installed.
  Future<void> _createCrashLogTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS crash_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL DEFAULT 'error',
        message TEXT NOT NULL,
        stack TEXT,
        route TEXT,
        actor_name TEXT,
        action TEXT,
        breadcrumbs TEXT,
        created_at TEXT NOT NULL
      )''');
    // The two ways it is read: newest first (the diagnostics screen), and by
    // actor (an owner asking which cashier's till keeps failing).
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_crash_created ON crash_log (created_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_crash_actor ON crash_log (actor_name, created_at DESC)');
  }

  /// v18: the audit log — who did what, when.
  ///
  /// Called from BOTH paths: a fresh install's `onCreate` and the v17 -> v18
  /// `onUpgrade`. Defining the schema once and applying it twice is the only
  /// way `migration_test.dart`'s "fresh installs match upgraded installs" can
  /// stay true, and a shop must not get a different database depending on when
  /// it installed.
  Future<void> _createAuditLogTable(Database db) async {
    // `actor_id` is NULL for the owner: `deleteStaffWithTombstone` anonymises
    // the staff table, and tying an audit row to a row that may be scrubbed
    // would leak the very name the tombstone exists to remove. The display name
    // is denormalised into `actor_name` so the row still reads without a join.
    await db.execute('''CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        entity TEXT NOT NULL,
        entity_id TEXT,
        actor_id INTEGER,
        actor_name TEXT NOT NULL,
        detail TEXT,
        created_at TEXT NOT NULL
      )''');
    // The three ways the log is read: the filtered control-relevant view the
    // activity screen uses on every load, everything on an entity (what
    // happened to THIS product), and everything by an actor in a window (what
    // did THIS cashier do today).
    //
    // `idx_audit_action` matters because `action IN (…)` filters a table where
    // sale rows dominate: without a leading `action` column SQLite walks
    // `created_at DESC` and discards every row that is not in the filter, so
    // the activity screen reads the whole recent log to show 50 rows of it.
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_log (action, created_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log (entity, entity_id, created_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_log (actor_id, created_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log (created_at DESC)');
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
      status TEXT NOT NULL DEFAULT 'open',
      -- Whether the server has this shift. A shift is opened OFFLINE and
      -- pushed later, and a re-push must not count the drawer twice.
      synced_to_backend INTEGER NOT NULL DEFAULT 0
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
      -- Whether the server has this cup. A cup is set up ONCE, on one phone,
      -- and it is the whole shop's shelf after that.
      synced_to_backend INTEGER NOT NULL DEFAULT 0,
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
    // The same declarations as `_onCreate`, so a fresh install and an upgraded
    // till can never diverge. `IF NOT EXISTS` throughout, because this runs for
    // every till below v12 and most of them already have some of these.
    await db.execute('''CREATE TABLE IF NOT EXISTS owner (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      name TEXT NOT NULL,
      pin_hash TEXT NOT NULL,
      email TEXT NOT NULL,
      shop_name TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS staff (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      pin_hash TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 1,
      remote_id TEXT,
      role TEXT NOT NULL DEFAULT 'cashier',
      username TEXT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS stock_adjustments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      delta INTEGER NOT NULL,
      reason TEXT,
      staff_name TEXT NOT NULL,
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
    // KRA's own QR payload lives on the sale, so a reprint scans to the real
    // verification page.
    //
    // It is added HERE, not in a versioned migration, because this helper runs
    // on BOTH a fresh install and the v13 upgrade. A column added only in a
    // versioned step would exist on every upgraded till and on no fresh one —
    // and the fresh one would fail to write a receipt KRA had already issued.
    await _ensureEtimsQrPayloadColumn(db);

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

    // --- Weight-stocked tanks -----------------------------------------------
    //
    // How many millilitres one kilogram of the product is: the bridge between a
    // tank's stock, which arrives on a scale, and the volume the pour maths
    // counts. 0 means "not stocked by weight", so every product that is not a
    // tank answers 0 and stays a volume product — an old row and a fresh install
    // describe the same shape.
    //
    // Added here as well as in the v22 migration step because this helper runs
    // from BOTH paths, and a column defined in only one of them is a column a
    // fresh install does not have.
    await db.execute(
        'ALTER TABLE products ADD COLUMN ml_per_kg REAL NOT NULL DEFAULT 0');

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
    // matched to a payment receipt, and the owner needs to be able to find those
    // and reconcile them. Defaults to 1 so every pre-existing row is verified.
    await db.execute(
        'ALTER TABLE sales ADD COLUMN payment_verified INTEGER NOT NULL DEFAULT 1');
    await db.execute('ALTER TABLE sales ADD COLUMN payment_confirmed_at TEXT');

    // --- Import rows needing attention -------------------------------------
    await _createImportNeedsAttentionTable(db);

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
    await _createReturnTables(db);
    await _createReceiptTables(db);
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
        role TEXT NOT NULL DEFAULT 'cashier',
        username TEXT
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
        remote_id TEXT,
        image_path TEXT
      )
    ''');
    // `unit`, `track_variants`, `ml_per_kg` and every other column added since
    // v11 are NOT written here. They are added by the ALTERs in the migration
    // steps — and `_createVariantsAndImportTables` runs its ALTERs on a database
    // this method has JUST created, so listing a column in both places is
    // `duplicate column name` on every fresh install.
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
        created_at TEXT NOT NULL,
        vat_rate_percent INTEGER,
        -- Whether the server has this sale. The till writes its ledger
        -- offline and pushes it when the phone can reach the server, and a
        -- phone that was offline pushes the same sale again — so the app has
        -- to know which ones the server already has.
        synced_to_backend INTEGER NOT NULL DEFAULT 0
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
    await _createAuditLogTable(db);
    await _createCrashLogTable(db);
    // The ledger, the payments and the tax columns. Declared in the same
    // helper the v26 upgrade uses, so a new till and an upgraded one cannot
    // diverge — the defect the v24 step introduced and v25 had to repair.
    await _createFoundationTables(db);

    // Indexes for query hotspots not covered by the core set above. Created
    // after the helper calls so the columns they add (payment_verified,
    // etims_status, track_variants) already exist.
    await db.execute(
        'CREATE INDEX idx_sales_payment_verified ON sales (payment_verified, created_at DESC)');
    await db
        .execute('CREATE INDEX idx_sales_etims_status ON sales (etims_status)');
    await db.execute('CREATE INDEX idx_products_active ON products (active)');
    await db.execute(
        'CREATE INDEX idx_products_track_variants ON products (track_variants)');
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

  /// Updates the owner's own details: the name, the shop's name, and the
  /// address the emailed codes go to.
  ///
  /// The PIN is NOT touched: it has its own flow, with its own confirmation and
  /// its own lockout, and a profile edit is not a way to change it.
  ///
  /// The shop name is written to the `owner` row AND to the workspace
  /// registry, because the registry is what the shell bar and the receipt
  /// header read. Updating one and not the other is how a shop ends up with two
  /// names on one screen.
  Future<void> updateOwnerProfile({
    required String name,
    required String shopName,
    required String email,
  }) async {
    final db = await database;
    await db.update(
      'owner',
      <String, Object?>{'name': name, 'shop_name': shopName, 'email': email},
      where: 'id = 1',
    );
    await WorkspaceService.register(
      workspaceKey: await WorkspaceService.activeWorkspaceKey(),
      // The tenant binding is untouched: a shop that is linked to the backend
      // stays linked, and a shop that is not stays unlinked. A name change is
      // not a linking change.
      tenantId: await WorkspaceService.activeTenantId(),
      shopName: shopName,
    );
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

  /// Writes an opening movement: the count a product or variant had when it
  /// entered the ledger.
  ///
  /// The opening row is what makes the ledger checkable: without it, every
  /// product's balance would read as wrong because the history that made it
  /// is not there.
  Future<void> _writeOpeningMovement(
    DatabaseExecutor db, {
    required int productId,
    int? variantId,
    required double balance,
  }) async {
    await db.insert('stock_movements', {
      'uuid': _newUuid(),
      'created_at': DateTime.now().toIso8601String(),
      'product_id': productId,
      'variant_id': variantId,
      'movement_type': StockMovementType.opening.wire,
      'qty_delta': balance,
      'unit_cost_minor': null,
      'reference_type': null,
      'reference_id': null,
      'batch_id': null,
      'staff_id': null,
      'staff_name': null,
      'note': 'Opening balance',
      'balance_after': balance,
    });
  }

  /// Writes one row of the stock ledger.
  ///
  /// [qtyDelta] is signed: negative for goods that left, positive for goods
  /// that arrived. [balanceAfter] is the count the row leaves behind, so a
  /// reader can follow the ledger without summing it — and the check that
  /// compares the two is what catches a writer that forgot to write a row.
  ///
  /// The movement is written by the same transaction as the change it
  /// describes. A movement and a count that disagree are worse than neither:
  /// one of them is a lie, and nothing says which.
  Future<void> _writeStockMovement(
    DatabaseExecutor db, {
    required int productId,
    int? variantId,
    required StockMovementType type,
    required double qtyDelta,
    int? unitCostMinor,
    String? referenceType,
    int? referenceId,
    int? batchId,
    int? staffId,
    String? staffName,
    String? note,
    required double balanceAfter,
    String? createdAt,
  }) async {
    await db.insert('stock_movements', {
      'uuid': _newUuid(),
      'created_at': createdAt ?? DateTime.now().toIso8601String(),
      'product_id': productId,
      'variant_id': variantId,
      'movement_type': type.wire,
      'qty_delta': qtyDelta,
      'unit_cost_minor': unitCostMinor,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'batch_id': batchId,
      'staff_id': staffId,
      'staff_name': staffName,
      'note': note,
      'balance_after': balanceAfter,
    });
  }

  /// The count a product's ledger says it should have.
  ///
  /// The sum of the movements, which is the truth the cached count has to
  /// agree with.
  Future<double> ledgerBalance(
    int productId, {
    int? variantId,
  }) async {
    final rows = await (await database).rawQuery(
      'SELECT COALESCE(SUM(qty_delta), 0) AS total FROM stock_movements '
      'WHERE product_id = ? AND variant_id IS ?',
      [productId, variantId],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// The ledger rows for one product, newest first.
  ///
  /// The stock history on a product's page, and what the ledger check reads.
  Future<List<StockMovement>> getStockMovements(
    int productId, {
    int? variantId,
    int limit = 100,
  }) async {
    final rows = await (await database).rawQuery(
      'SELECT * FROM stock_movements WHERE product_id = ? '
      'AND variant_id IS ? ORDER BY id DESC LIMIT ?',
      [productId, variantId, limit],
    );
    return rows.map(StockMovement.fromMap).toList();
  }

  /// Writes a correction so a count and its ledger agree again.
  ///
  /// The correction is a NEW row, never an edit. The ledger is append-only,
  /// so the mistake that caused the difference is still there to be read — and
  /// "the ledger was wrong, and here is the truth" is a claim a shop can
  /// check later.
  ///
  /// The count is what the shop has been selling from, so it is what the
  /// ledger is corrected TO. The owner has looked at the difference before
  /// this is called; this is the part where the books are made to agree.
  Future<void> repairLedgerDifference(LedgerDifference difference) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE products SET stock_qty = ?, updated_at = ? WHERE id = ?',
        [
          difference.counted,
          DateTime.now().toIso8601String(),
          difference.productId,
        ],
      );
      await _writeStockMovement(
        txn,
        productId: difference.productId,
        variantId: difference.variantId,
        type: StockMovementType.correction,
        qtyDelta: difference.counted - difference.ledger,
        note: 'Ledger corrected to match the count',
        balanceAfter: difference.counted,
      );
    });
  }

  /// The parts a sale was paid in.
  ///
  /// The order is the order they were taken, so a split sale reads the way
  /// the customer paid it.
  Future<List<SalePayment>> getSalePayments(int saleId) async {
    final rows = await (await database).query('sale_payments',
        where: 'sale_id = ?', whereArgs: [saleId], orderBy: 'id');
    return rows.map(SalePayment.fromMap).toList();
  }

  /// Every product whose count disagrees with its ledger.
  ///
  /// The check the owner can run. An empty list is the answer a healthy
  /// database gives, and it is the answer the migration has to produce on a
  /// shop with years of history.
  Future<List<LedgerDifference>> findLedgerDifferences() async {
    final rows = await (await database).rawQuery('''
      SELECT p.id AS product_id,
             p.name AS product_name,
             p.stock_qty AS counted,
             COALESCE((
               SELECT SUM(m.qty_delta) FROM stock_movements m
                WHERE m.product_id = p.id AND m.variant_id IS NULL
             ), 0) AS ledger
        FROM products p
    ''');
    final differences = <LedgerDifference>[];
    for (final row in rows) {
      final double counted = (row['counted'] as num?)?.toDouble() ?? 0;
      final double ledger = (row['ledger'] as num?)?.toDouble() ?? 0;
      // A tenth of a unit is the tolerance: a measured pour is a ratio, and
      // 25 x (30/750) is 1.0000000000000002 in binary floating point.
      if ((counted - ledger).abs() > 0.1) {
        differences.add(LedgerDifference(
          productId: row['product_id'] as int,
          productName: row['product_name'] as String? ?? '',
          variantId: null,
          counted: counted,
          ledger: ledger,
        ));
      }
    }
    return differences;
  }

  /// Writes a variant, insert or update by id.
  ///
  /// Money is not defaulted to the parent on update. A variant with its own
  /// price that silently falls back to the parent's on the next save is a price
  /// change nobody made.
  Future<int> upsertVariant(ProductVariant variant) async {
    final map = variant.toMap();
    if (variant.id == null) {
      final db = await database;
      final id = await db.insert('product_variants', map..remove('id'));
      await _recordNewVariantCount(db, variant.productId, id, variant.stockQty);
      return id;
    }
    await (await database).update('product_variants', map,
        where: 'id = ?', whereArgs: [variant.id]);
    return variant.id!;
  }

  /// A new variant's count, and the product's count beside it.
  ///
  /// A variant that joins a product changes the product's aggregate, and the
  /// aggregate is what the till checks and the dashboard shows. So the
  /// product's count is rewritten from the variants, and the product's ledger
  /// gets a row that mirrors the variant's — because a product sold as
  /// variants and a variant are two views of ONE fact, and the ledger has to
  /// say so in both places. Without this the product's history and the
  /// variant's history disagree, and one of them is a lie.
  ///
  /// A product that does NOT track its variants keeps its own count, and the
  /// variant's count is beside it rather than inside it: nothing moves.
  Future<void> _recordNewVariantCount(
    DatabaseExecutor db,
    int productId,
    int variantId,
    double stockQty,
  ) async {
    await _writeOpeningMovement(
      db,
      productId: productId,
      variantId: variantId,
      balance: stockQty,
    );
    if (!await _productTracksVariants(db, productId)) return;
    final double aggregate = await _aggregateStock(db, productId);
    final double previous = await _productCount(db, productId);
    await db.rawUpdate(
      'UPDATE products SET stock_qty = ?, updated_at = ? WHERE id = ?',
      [aggregate, DateTime.now().toIso8601String(), productId],
    );
    await _writeStockMovement(
      db,
      productId: productId,
      type: StockMovementType.opening,
      qtyDelta: aggregate - previous,
      note: 'Variant added',
      balanceAfter: aggregate,
    );
  }

  /// Whether a product's count is the aggregate of its variants.
  Future<bool> _productTracksVariants(
      DatabaseExecutor db, int productId) async {
    final rows = await db.query('products',
        columns: ['track_variants'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1);
    if (rows.isEmpty) return false;
    return ((rows.first['track_variants'] as num?)?.toInt() ?? 0) == 1;
  }

  /// The sum of a product's active variants' counts.
  Future<double> _aggregateStock(DatabaseExecutor db, int productId) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(stock_qty), 0) AS total FROM product_variants '
      'WHERE product_id = ? AND active = 1',
      [productId],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// The count a product's row holds.
  Future<double> _productCount(DatabaseExecutor db, int productId) async {
    final rows = await db.query('products',
        columns: ['stock_qty'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1);
    if (rows.isEmpty) return 0;
    return (rows.first['stock_qty'] as num?)?.toDouble() ?? 0;
  }

  Future<void> deleteVariant(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn
          .delete('product_barcodes', where: 'variant_id = ?', whereArgs: [id]);
      await txn.delete('product_variants', where: 'id = ?', whereArgs: [id]);
    });
  }

  // Transaction-aware variants of the above, so a save that touches N rows
  // can run them in one fsync instead of N.
  Future<int> upsertVariantInTransaction(
      Transaction txn, ProductVariant variant) async {
    final map = variant.toMap();
    if (variant.id == null) {
      final id = await txn.insert('product_variants', map..remove('id'));
      await _recordNewVariantCount(
        txn,
        variant.productId,
        id,
        variant.stockQty,
      );
      return id;
    }
    await txn.update('product_variants', map,
        where: 'id = ?', whereArgs: [variant.id]);
    return variant.id!;
  }

  Future<void> deleteVariantInTransaction(Transaction txn, int id) async {
    await txn
        .delete('product_barcodes', where: 'variant_id = ?', whereArgs: [id]);
    await txn.delete('product_variants', where: 'id = ?', whereArgs: [id]);
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
    String? columnMap,
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
      'column_map': columnMap,
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

  /// Resolves every open problem recorded from one sheet of one source.
  ///
  /// A problem is a statement about what ONE import of ONE sheet left behind,
  /// so the next import of that same sheet supersedes all of them — whether it
  /// read them, replaced them, or refused the file outright. Without this the
  /// list only ever grows: a re-import cannot clear the rows a previous import
  /// failed on, which is exactly what the dashboard's "re-import the
  /// spreadsheet to finish that update" tells the owner to do. A refused import
  /// resolves them too, because a file whose layout cannot be mapped leaves
  /// nothing actionable behind it and a permanent warning is worse than none.
  Future<void> resolveImportProblemsForSheet({
    required String source,
    required String sheetName,
  }) async {
    await (await database).update(
      'import_needs_attention',
      {'resolved': 1},
      where: 'resolved = 0 AND source = ? AND sheet_name = ?',
      whereArgs: [source, sheetName],
    );
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

  /// The VAT rate that applied to a particular sale.
  ///
  /// Reads the rate stored on the sale row (`vat_rate_percent`), which is the
  /// rate in force when the sale was committed. Falls back to the current
  /// rate for legacy rows written before the column existed — a reprint of a
  //  pre-v23 sale shows today's rate rather than crashing on a NULL column.
  Future<int> vatRateForSale(Map<String, dynamic> saleRow,
      {int? fallback}) async {
    final stored = saleRow['vat_rate_percent'] as int?;
    if (stored != null && stored >= 0 && stored <= 100) return stored;
    return fallback ?? await getVatRatePercent();
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

  /// Sets the low-stock limit for every active product.
  ///
  /// A shop deciding its limit is 8, not 5, is not a decision about 214
  /// products one at a time — and an owner who will not tap through an editor
  /// 214 times ends up with a dashboard warning about nothing. One write, one
  /// count returned, one audit row.
  ///
  /// ONE column in ONE statement, deliberately NOT a read-then-`upsertProducts`
  /// round-trip: `upsertProducts` rewrites the whole row through `toMap`, and
  /// the fields a limit does not speak about — `unit`, `track_variants`,
  /// `image_path` — cannot survive that undamaged, so a limit change used to
  /// flatten every litre-sold product to "each", clear every variant flag and
  /// null every photo path in the shop.
  Future<int> setLowStockLimit(int limit) async {
    return (await database).update(
      'products',
      {'reorder_level': limit},
      where: 'active = 1',
    );
  }

  Future<int> upsertProduct(Product p) async {
    final db = await database;
    if (p.id == null) {
      final int id = await db.insert('products', p.toMap());
      // A product that arrives with stock arrives with a reason for having
      // it, and the ledger records that reason. Without this row the count
      // would have no history, and the ledger check would read every product
      // as wrong.
      await _writeOpeningMovement(db, productId: id, balance: p.stockQty);
      return id;
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

  /// Same as [upsertProduct] but inside an already-open transaction, so a
  /// product row and its variants commit in one all-or-nothing unit. Without
  /// this a variant save that fails after the product insert leaves a product
  /// the editor still thinks is new — and the next Save inserts it again.
  Future<int> upsertProductInTransaction(Transaction txn, Product p) async {
    if (p.id == null) {
      return txn.insert('products', p.toMap());
    } else {
      final values = p.toMap();
      if (p.remoteId == null) values.remove('remote_id');
      final updated = await txn
          .update('products', values, where: 'id = ?', whereArgs: [p.id]);
      if (updated == 0) {
        values.remove('id');
        return txn.insert('products', values);
      }
      return p.id!;
    }
  }

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

  /// Sets (or clears, with null) a product's photograph path.
  ///
  /// Only the photograph and the row's freshness are written. `upsertProduct`
  /// rewrites the whole row, so routing a photograph through it would let every
  /// unrelated edit overwrite the path with whatever was in the product object
  /// that happened to be passed — and the editor's product object is built
  /// before the photograph is imported.
  ///
  /// `updated_at` moves with the photograph, and it has to: a photograph is
  /// REPLACED by writing a new picture OVER the file at the same path, so the
  /// path in the column does not change and cannot tell the tile that what it
  /// is drawing is out of date. The till and the inventory row pass this
  /// timestamp to the photo widget as its revision, so a row whose timestamp
  /// has not moved is a row whose photograph is known to be the old one.
  Future<void> setProductImage(String? relativePath, int productId) async {
    final db = await database;
    await db.update(
      'products',
      <String, Object?>{
        'image_path': relativePath,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[productId],
    );
  }

  /// Clears every cached `remote_id`, on products and on staff.
  ///
  /// Called when the tenant this shop is bound to changes. The ids are minted
  /// inside one tenant's namespace, so keeping them after a relink would mean
  /// addressing foreign rows — see `BackendService._assertRowsInScope`.
  ///
  /// Clears the ids only. The rows are untouched: a product the shop still sells
  /// is still its product, and the next sync lets the server mint a fresh id
  /// under the tenant the shop is actually bound to now.
  Future<void> clearAllRemoteIds() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('products', <String, Object?>{'remote_id': null});
      await txn.update('staff', <String, Object?>{'remote_id': null});
    });
  }

  /// Clears every staff deletion tombstone.
  ///
  /// A tombstone replays "this cashier was removed" by `remote_id`, so after a
  /// tenant change the replay would name a row in the old tenant's namespace.
  /// Dropping them is the honest answer: the next sync under the new tenant
  /// states the roster as it is now, and a removed cashier is simply absent
  /// from it.
  Future<void> clearAllDeletionTombstones() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('staff_deletion_tombstones');
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
      // The ledger row, in the same transaction as the correction. A count
      // that moved without saying why is the exact thing the ledger exists to
      // prevent.
      final double balance = await _productBalanceAfter(txn, adj.productId);
      await _writeStockMovement(
        txn,
        productId: adj.productId,
        type: StockMovementType.adjustment,
        qtyDelta: adj.delta.toDouble(),
        referenceType: 'adjustment',
        staffId: staffId,
        staffName: adj.staffName,
        note: adj.reason,
        balanceAfter: balance,
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
    // Resolved before the transaction opens: reads that touch the database must
    // not happen inside the transaction, or sqflite_ffi deadlocks on a read
    // inside a write transaction.
    final tillCode = await getTillCode();
    final vatRatePercent = await getVatRatePercent();

    return db.transaction<int>((txn) async {
      // A line's fraction of its container — the shared rule, so a sale and a
      // return agree on what a portion of a bottle is.
      double portionFactor(SaleItem item, double containerMl) =>
          _portionFactor(item, containerMl);

      // Read every product this sale touches once: its stock is needed for the
      // availability check, its container size for the fraction, and its tax
      // class for the line's VAT snapshot.
      final stockByProduct = <int, double>{};
      final containerMlByProduct = <int, double>{};
      final taxClassByProduct = <int, String>{};
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
        taxClassByProduct[productId] =
            current.first['tax_class'] as String? ?? 'standard';
      }

      // The variants this sale sells, read inside the transaction.
      //
      // A variant's own count used to be adjusted in a SECOND transaction
      // after the sale had already been committed. A crash, a flat battery or
      // a killed process in that window left a sold bottle and an unchanged
      // count — and the error was swallowed, so nothing was ever reported.
      // Reading the row here and deducting it below means the sale, the count
      // and the parent's aggregate either all land or none of them do.
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

      // The units each line takes, split by where they come from.
      //
      // A line that names a variant takes from the VARIANT's count; a line
      // that does not takes from the product's own count. The two are
      // different, and the product's count is only an aggregate of the
      // variants' when the product tracks variants — so a sale of a variant
      // must be checked against the variant, or a product whose aggregate has
      // drifted refuses a sale the till can actually make.
      final variantUnitsByProduct = <int, double>{};
      final directUnitsByProduct = <int, double>{};
      final requiredByVariant = <int, double>{};
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
          if (available + _volumeTolerance < entry.value) {
            final offending =
                items.firstWhere((it) => it.variantId == entry.key);
            throw StateError('Not enough stock for ${offending.productName}');
          }
        }
        for (final entry in directUnitsByProduct.entries) {
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

      // The VAT on this sale, computed once from the lines and stored.
      //
      // Prices are VAT-inclusive, so the VAT is extracted from the discounted
      // gross rather than added to it. It is computed HERE, at the moment of
      // sale, and never recomputed: a reprint, a report and the eTIMS payload
      // all read the stored figure, so the paper and the tax filing can never
      // disagree about the same transaction.
      final int saleVatMinor = items.fold<int>(
        0,
        (sum, it) =>
            sum +
            vatComponentOf(it.total, ratePercent: vatRatePercent).minorUnits,
      );
      final int saleTaxableMinor = total.minorUnits - saleVatMinor;

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
        'vat_rate_percent': vatRatePercent,
        'vat_minor': saleVatMinor,
        'taxable_minor': saleTaxableMinor,
        'document_type': 'sale',
      });
      for (final it in items) {
        final fraction = portionFactor(it, containerMlByProduct[it.productId]!);
        final int lineVatMinor =
            vatComponentOf(it.total, ratePercent: vatRatePercent).minorUnits;
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': it.productId,
          'product_name': it.productName,
          'qty': it.qty,
          'unit_price': it.unitPrice.minorUnits,
          'unit_cost': it.unitCost.minorUnits,
          'portion': it.portion,
          'portion_ml': it.portionMl,
          // The variant the line was sold as. Recorded as a snapshot, because
          // the owner renames "Dark" to "Black" next month and a reprint of
          // today's receipt must still say which size was sold.
          'variant_id': it.variantId,
          'variant_name': it.variantName,
          // The tax on this line, snapshotted at the moment of sale. The
          // product's own tax class can change tomorrow; today's receipt must
          // still carry today's figure.
          'tax_class': taxClassByProduct[it.productId] ?? 'standard',
          'vat_rate_bps': vatRatePercent * 100,
          'vat_minor': lineVatMinor,
          'taxable_minor': it.total.minorUnits - lineVatMinor,
        });
        final variantId = it.variantId;
        if (variantId != null) {
          // The variant's own count, in the same transaction as the sale.
          // Clamped at zero for the same reason the parent's is: the money is
          // already taken, and a clamped count that needs a stock take beats a
          // till that refuses to hand over change.
          await txn.rawUpdate(
            'UPDATE product_variants SET stock_qty = MAX(0, stock_qty - ?) WHERE id = ?',
            [it.qty * fraction, variantId],
          );
        }
      }

      // The product's own count, set rather than decremented.
      //
      // For a product that tracks variants, its count IS the aggregate of its
      // active variants, and it is that number the till checks and the
      // dashboard shows. Rewriting it from the variants — inside the same
      // transaction as the deduction it is correcting — keeps the parent
      // honest, and it also HEALS an aggregate that had drifted: a variant
      // added after the last reconciliation, or one an older till deducted
      // outside the sale.
      //
      // A product with variants that does NOT track them keeps its own count,
      // and both counts move: the product's for what the shop thinks it sold,
      // the variant's for what it really sold.
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
      // The stock ledger.
      //
      // One row per stock row this sale touched, written in the same
      // transaction as the deduction. A product sold as variants gets a row
      // for the variant that was sold AND a row for the product's aggregate,
      // because both counts are real and both have to be explainable.
      //
      // The balance on each row is the count the row leaves behind, read back
      // from the count the transaction has just written — so the ledger is
      // never a second, separately-maintained truth.
      for (final it in items) {
        final fraction = portionFactor(it, containerMlByProduct[it.productId]!);
        final double units = it.qty * fraction;
        final variantId = it.variantId;
        if (variantId != null) {
          final double balance = await _variantBalanceAfter(txn, variantId);
          await _writeStockMovement(
            txn,
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
            await _productBalanceAfter(txn, it.productId);
        await _writeStockMovement(
          txn,
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

      // The payment.
      //
      // One row per part of the tender. A sale paid in one go has one row; a
      // sale paid in several has several, and the sum of their amounts is the
      // sale's total. That sum is an invariant, and a test holds it.
      await txn.insert('sale_payments', {
        'uuid': _newUuid(),
        'sale_id': saleId,
        'method': paymentMethod,
        // What was paid, without the change. The change is not payment.
        'amount_minor': paid.minorUnits - change.minorUnits,
        'tendered_minor': paid.minorUnits,
        'change_minor': change.minorUnits,
        'reference': paymentReference,
        'status': paymentVerified ? 'confirmed' : 'unverified',
        'pending_payment_id': null,
        'created_at': now,
      });

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
          'document_type': 'sale',
        });
      }
      return saleId;
    });
  }

  /// The count a variant is left with, read from the row the transaction has
  /// just written.
  Future<double> _variantBalanceAfter(Transaction txn, int variantId) async {
    final rows = await txn.query('product_variants',
        columns: ['stock_qty'],
        where: 'id = ?',
        whereArgs: [variantId],
        limit: 1);
    if (rows.isEmpty) return 0;
    return (rows.first['stock_qty'] as num?)?.toDouble() ?? 0;
  }

  /// The count a product is left with, read from the row the transaction has
  /// just written.
  Future<double> _productBalanceAfter(Transaction txn, int productId) async {
    final rows = await txn.query('products',
        columns: ['stock_qty'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1);
    if (rows.isEmpty) return 0;
    return (rows.first['stock_qty'] as num?)?.toDouble() ?? 0;
  }

  // ---------------- eTIMS issuance queue ----------------

  /// Sales still waiting for a KRA receipt number, oldest first.
  ///
  /// Oldest first so numbering is uploaded in the order it was issued. KRA
  /// rejects a batch whose sequence has a gap, so flushing newest-first would
  /// trade a queue problem for a compliance one. Rows whose sale has been
  /// permanently rejected are excluded: retrying them achieves nothing and one
  /// rejected row must not block every receipt behind it.
  Future<List<PendingEtimsReceipt>> getPendingEtimsReceipts({
    int limit = 200,
  }) async {
    final rows = await (await database).rawQuery('''
      SELECT p.* FROM pending_etims p
      JOIN sales s ON s.id = p.sale_id
      WHERE s.etims_status != ?
      ORDER BY p.created_at ASC
      LIMIT ?
    ''', [EtimsStatus.rejected, limit]);
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
    final rows = await (await database).rawQuery('''
      SELECT COUNT(*) AS c FROM pending_etims p
      JOIN sales s ON s.id = p.sale_id
      WHERE s.etims_status != ?
    ''', [EtimsStatus.rejected]);
    return (rows.first['c'] as int?) ?? 0;
  }

  /// The pending queue row for one sale, so the inline post-sale attempt can
  /// target this customer's receipt instead of the oldest stuck one.
  Future<PendingEtimsReceipt?> getPendingEtimsReceiptBySaleId(
      int saleId) async {
    final rows = await (await database).rawQuery('''
      SELECT p.* FROM pending_etims p
      JOIN sales s ON s.id = p.sale_id
      WHERE p.sale_id = ? AND s.etims_status != ?
      LIMIT 1
    ''', [saleId, EtimsStatus.rejected]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return PendingEtimsReceipt(
      saleId: row['sale_id'] as int,
      receiptNumber: row['receipt_number'] as String,
      attempts: (row['attempts'] as int?) ?? 0,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastError: row['last_error'] as String?,
    );
  }

  /// Records the KRA receipt number and KRA's own `qr_payload` on the sale and
  /// clears the queue row.
  ///
  /// Idempotent: replaying an already-resolved upload is a no-op rather than a
  /// second invoice, because the queue row is what proves this sale has not
  /// been issued yet.
  Future<void> resolveEtimsReceipt({
    required int saleId,
    required String kraReceiptNumber,
    String? qrPayload,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'sales',
        {
          'etims_status': EtimsStatus.issued,
          'etims_receipt_number': kraReceiptNumber,
          if (qrPayload != null) 'etims_qr_payload': qrPayload,
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

  /// Puts rejected receipts back in the queue.
  ///
  /// A permanent rejection is permanent for the receipt that caused it: the
  /// same payload will be refused the same way. It is NOT permanent for the
  /// shop — the owner fixes the cause (a wrong TIN, a bad buyer PIN, a KRA
  /// outage that briefly answered 400) and then wants those invoices filed.
  ///
  /// So a rejection is not a dead end: it is a receipt waiting for someone to
  /// say "try again". The attempt count is reset, because the attempts that
  /// led to the refusal say nothing about the next attempt.
  ///
  /// Returns how many receipts were put back, so the caller can say "3
  /// receipts queued" rather than "something happened".
  Future<int> requeueRejectedEtimsReceipts() async {
    final db = await database;
    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final sales = await txn.update(
        'sales',
        {'etims_status': EtimsStatus.pending},
        where: 'etims_status = ?',
        whereArgs: [EtimsStatus.rejected],
      );
      await txn.rawUpdate(
        '''UPDATE pending_etims
              SET attempts = 0, last_error = NULL, updated_at = ?
            WHERE sale_id IN (SELECT id FROM sales WHERE etims_status = ?)''',
        [now, EtimsStatus.pending],
      );
      return sales;
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

  /// Ascending sales after [after], used by Sheets sync so a shop with more
  /// than one batch's worth of unsynced sales does not lose the older ones.
  ///
  /// Returns oldest first so `appendSales` can walk the backlog in bounded
  /// batches without skipping the tail.
  /// The sales the server has not seen yet, oldest first.
  ///
  /// The push reads these and the server keys them on the sale's own id, so
  /// the same sale pushed twice is one sale on the server. The order matters:
  /// the ledger is a story, and a story read from the end is not a story.
  Future<List<Sale>> getUnsyncedSales({int limit = 500}) async {
    final db = await database;
    final rows = await db.query(
      'sales',
      where: 'synced_to_backend = 0',
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    if (rows.isEmpty) return [];
    Map<dynamic, List<Map<String, dynamic>>> itemsBySale =
        <dynamic, List<Map<String, dynamic>>>{};
    final saleIds = rows.map((row) => row['id']).toList();
    final itemRows = await db.query(
      'sale_items',
      where: 'sale_id IN (${List.filled(saleIds.length, '?').join(',')})',
      whereArgs: saleIds,
    );
    for (final item in itemRows) {
      (itemsBySale[item['sale_id']] ??= []).add(item);
    }
    final sales = <Sale>[];
    for (final r in rows) {
      final Sale sale = Sale.fromMap(r);
      sales.add(Sale(
        id: sale.id,
        staffName: sale.staffName,
        total: sale.total,
        profit: sale.profit,
        createdAt: sale.createdAt,
        paymentMethod: sale.paymentMethod,
        paymentReference: sale.paymentReference,
        amountTendered: sale.amountTendered,
        changeGiven: sale.changeGiven,
        items: (itemsBySale[r['id']] ?? const <Map<String, dynamic>>[])
            .map(SaleItem.fromMap)
            .toList(),
      ));
    }
    return sales;
  }

  /// Marks these sales as pushed.
  ///
  /// Only the ids the server confirmed. A sale the server did not accept is
  /// still unsynced, and the next push tries it again — which is the whole
  /// point of keeping the flag on the row.
  Future<void> markSalesSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.rawUpdate(
      'UPDATE sales SET synced_to_backend = 1 WHERE id IN '
      '(${List.filled(ids.length, '?').join(',')})',
      ids,
    );
  }

  /// The shifts the server has not seen yet.
  ///
  /// The cash figures come from the shift's own reconciliation — the LAST
  /// one, because a drawer can be counted twice while the person checks the
  /// figure, and the later count replaces the earlier one.
  Future<List<Map<String, dynamic>>> getUnsyncedShifts({
    int limit = 200,
  }) async {
    final db = await database;
    final rows = await db.query(
      'shifts',
      where: 'synced_to_backend = 0',
      orderBy: 'start_time ASC, id ASC',
      limit: limit,
    );
    if (rows.isEmpty) return [];
    final ids = rows.map((row) => row['id']).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final reconciliations = await db.query(
      'reconciliations',
      where: 'shift_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'recorded_at DESC, id DESC',
    );
    final latestByShift = <int, Map<String, dynamic>>{};
    for (final row in reconciliations) {
      final int shiftId = row['shift_id'] as int;
      latestByShift.putIfAbsent(shiftId, () => row);
    }
    return rows.map((row) {
      final int shiftId = row['id'] as int;
      final Map<String, dynamic>? reconciliation = latestByShift[shiftId];
      return <String, dynamic>{
        ...row,
        'expected_cash': reconciliation?['expected_cash'] ?? 0,
        'counted_cash': reconciliation?['counted_cash'] ?? 0,
      };
    }).toList();
  }

  /// Marks these shifts as pushed.
  Future<void> markShiftsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.rawUpdate(
      'UPDATE shifts SET synced_to_backend = 1 WHERE id IN '
      '(${List.filled(ids.length, '?').join(',')})',
      ids,
    );
  }

  /// The shot cups the server has not seen yet.
  Future<List<ShotCup>> getUnsyncedShotCups({int limit = 500}) async {
    final rows = await (await database).query(
      'shot_cups',
      where: 'synced_to_backend = 0',
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(ShotCup.fromMap).toList();
  }

  /// Marks these shot cups as pushed.
  Future<void> markShotCupsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.rawUpdate(
      'UPDATE shot_cups SET synced_to_backend = 1 WHERE id IN '
      '(${List.filled(ids.length, '?').join(',')})',
      ids,
    );
  }

  /// Records a return: goods going back to the shop, and money going back to
  /// the customer.
  ///
  /// ## WHAT IT IS ONE TRANSACTION FOR
  ///
  /// The return, its lines, the stock movements and the drawer's cash all move
  /// together, or none of them move. A return that wrote the record and then
  /// failed to put the goods back would leave the shelf short and the customer
  /// refunded — and nothing in the app would say so.
  ///
  /// ## THE RULES
  ///
  /// * **The cumulative returned quantity per sale line never exceeds the sold
  ///   quantity.** A bottle can be returned once. The check is against what
  ///   has ALREADY been returned, not just against this return, so the same
  ///   bottle cannot be returned twice by two returns.
  /// * **The refund per line is the line total scaled by the returned
  ///   fraction, rounded half-up**, and the return's total is the SUM of the
  ///   line refunds. Not the sale's total scaled — the sum of the lines, so
  ///   there is no rounding drift between the two.
  /// * **Restocking puts the goods back at the sale line's cost.** A write-off
  ///   does not: the goods are damaged or expired, and the shelf does not get
  ///   them.
  /// * **A cash refund reduces the expected cash of the shift that is open
  ///   NOW**, not the shift the sale was rung in. The money left the drawer
  ///   that is open today. With no shift open, a cash refund is refused —
  ///   there is no drawer to take the money out of.
  /// * **A sale with an unverified mobile-money payment cannot be returned**,
  ///   because the money may never have arrived.
  Future<int> recordReturn({
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

    final db = await database;
    return db.transaction<int>((txn) async {
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
          !await _paymentIsVerified(txn, sale.id!)) {
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
      final now = DateTime.now().toIso8601String();

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
        if (already + draft.qty > soldQty + _qtyEpsilon) {
          throw StateError(
            'More was returned than was sold on that line',
          );
        }

        // The refund for the line: the line total scaled by the returned
        // fraction, rounded half-up. The line total is the UNIT price times
        // the quantity sold, so a half-bottle returns half the line.
        final int lineTotal = _roundHalfUp(sold.unitPrice.minorUnits * soldQty);
        final int refund = _roundHalfUp(lineTotal * (draft.qty / soldQty));
        final int soldVat = sold.vatMinor ?? 0;
        final int lineVat = _roundHalfUp(soldVat * (draft.qty / soldQty));
        totalMinor += refund;
        vatMinor += lineVat;
        profitMinor += _roundHalfUp(
          sold.unitCost.minorUnits * soldQty * (draft.qty / soldQty),
        );

        // The goods: back on the shelf, or written off.
        //
        // A write-off writes a row too — the ledger is append-only, and the
        // missing bottle has to be somewhere. It just does not put the
        // quantity back on the shelf.
        final double units = draft.qty * _portionFactor(sold, 0);
        if (draft.restock) {
          final double balance =
              await _productBalanceAfter(txn, sold.productId);
          await _writeStockMovement(
            txn,
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
          //
          // The product's own `stock_qty` is a cached balance, and the rule
          // in this app is that it is updated in the same transaction as the
          // movement that caused it. A movement with no count behind it is a
          // ledger that disagrees with the shelf, and the check that compares
          // the two is what catches it — but only if the count is moved here.
          await _restoreStockCount(
            txn,
            productId: sold.productId,
            variantId: sold.variantId,
            units: units,
          );
        } else {
          final double balance =
              await _productBalanceAfter(txn, sold.productId);
          await _writeStockMovement(
            txn,
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

      for (final ReturnLineDraft draft in lines) {
        final SaleItem sold = saleItems[draft.saleItemId]!;
        final int lineTotal =
            _roundHalfUp(sold.unitPrice.minorUnits * sold.qty);
        await txn.insert('sale_return_items', {
          'return_id': returnId,
          'sale_item_id': draft.saleItemId,
          'product_id': sold.productId,
          'product_name': sold.productName,
          'qty': draft.qty,
          'unit_price': sold.unitPrice.minorUnits,
          'unit_cost': sold.unitCost.minorUnits,
          'refund_minor': _roundHalfUp(lineTotal * (draft.qty / sold.qty)),
          'vat_minor': _roundHalfUp(
            (sold.vatMinor ?? 0) * (draft.qty / sold.qty),
          ),
          'portion': sold.portion,
          'portion_ml': sold.portionMl,
          'restock': draft.restock ? 1 : 0,
          'restock_reason': draft.restockReason,
        });
      }

      return returnId;
    });
  }

  /// Puts [units] back on the shelf, in the same transaction as the movement.
  ///
  /// The shape mirrors the sale's deduction exactly, in reverse: a variant
  /// gets its own count back, and a product that tracks variants has its
  /// aggregate REWRITTEN from its variants — the same healing the sale does,
  /// so a return cannot leave a parent that has drifted.
  Future<void> _restoreStockCount(
    DatabaseExecutor txn, {
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
  ///
  /// A mobile-money sale taken while the phone was offline is a real sale —
  /// the customer paid — but the payment was never confirmed, and a refund
  /// against money that never arrived is money the shop does not have.
  Future<bool> _paymentIsVerified(DatabaseExecutor txn, int saleId) async {
    // The flag is on the SALE, not on the payment row: a sale taken while the
    // phone was offline was recorded with `payment_verified = 0`, and that is
    // the flag the return has to read.
    final rows = await txn.rawQuery(
      'SELECT payment_verified FROM sales WHERE id = ? LIMIT 1',
      [saleId],
    );
    if (rows.isEmpty) return true;
    return ((rows.first['payment_verified'] as num?)?.toInt() ?? 1) == 1;
  }

  /// A tiny allowance for the arithmetic of a fraction of a bottle.
  ///
  /// A third of a bottle is not exactly representable, and a customer who
  /// returns "a third" should not be refused because 0.333 + 0.333 is a hair
  /// short of 1.
  static const double _qtyEpsilon = 0.0001;

  /// Rounds half away from zero, in minor units.
  ///
  /// The money rule everywhere in this app: a half rounds UP, because
  /// rounding a refund DOWN is how a shop quietly keeps a cent of every
  /// return.
  static int _roundHalfUp(double value) {
    if (value >= 0) {
      return value.floor() + (value - value.floor() >= 0.5 ? 1 : 0);
    }
    final int truncated = value.ceil();
    return truncated - (truncated - value >= 0.5 ? 1 : 0);
  }

  /// The returns recorded against a sale, newest first.
  Future<List<SaleReturn>> getReturnsForSale(int saleId) async {
    final db = await database;
    final rows = await db.query(
      'sale_returns',
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'created_at DESC, id DESC',
    );
    final returns = <SaleReturn>[];
    for (final row in rows) {
      final itemRows = await db.query(
        'sale_return_items',
        where: 'return_id = ?',
        whereArgs: [row['id']],
        orderBy: 'id ASC',
      );
      returns.add(
        SaleReturn.fromMap(row).let(
          (r) => SaleReturn(
            id: r.id,
            saleId: r.saleId,
            kind: r.kind,
            reason: r.reason,
            total: r.total,
            vatTotal: r.vatTotal,
            profit: r.profit,
            refundMethod: r.refundMethod,
            paymentReference: r.paymentReference,
            staffId: r.staffId,
            staffName: r.staffName,
            createdAt: r.createdAt,
            items: itemRows.map(SaleReturnItem.fromMap).toList(),
          ),
        ),
      );
    }
    return returns;
  }

  /// How much of each sale line has already come back.
  ///
  /// The stepper in the return flow is limited by this: a bottle can be
  /// returned once, and the second time round there is nothing left to
  /// return.
  Future<Map<int, double>> getReturnedQuantitiesForSale(int saleId) async {
    final rows = await (await database).rawQuery(
      'SELECT ri.sale_item_id, COALESCE(SUM(ri.qty), 0) AS returned_qty '
      'FROM sale_return_items ri '
      'JOIN sale_returns r ON r.id = ri.return_id '
      'WHERE r.sale_id = ? '
      'GROUP BY ri.sale_item_id',
      [saleId],
    );
    return <int, double>{
      for (final row in rows)
        row['sale_item_id'] as int: (row['returned_qty'] as num).toDouble(),
    };
  }

  /// How much of each of several sales has already come back.
  ///
  /// ONE query for the whole list, because the ledger shows a row per sale
  /// and a row that asked for its own figures would be a query per row.
  ///
  /// The answer is a map from sale id to the fraction of it that has come
  /// back: 0 for a sale that has not been touched, and anything above 0 for
  /// one that has.
  Future<Map<int, double>> getReturnedFractionsForSales(
    List<int> saleIds,
  ) async {
    if (saleIds.isEmpty) return <int, double>{};
    final rows = await (await database).rawQuery(
      'SELECT r.sale_id AS sale_id, COALESCE(SUM(i.qty), 0) AS returned_qty, '
      'COALESCE(SUM(s.qty), 0) AS sold_qty '
      'FROM sale_return_items i '
      'JOIN sale_returns r ON r.id = i.return_id '
      'JOIN sale_items s ON s.id = i.sale_item_id '
      'WHERE r.sale_id IN (${List.filled(saleIds.length, '?').join(',')}) '
      'GROUP BY r.sale_id',
      saleIds,
    );
    final Map<int, double> fractions = <int, double>{};
    for (final row in rows) {
      final int saleId = row['sale_id'] as int;
      final double sold = (row['sold_qty'] as num?)?.toDouble() ?? 0;
      final double returned = (row['returned_qty'] as num?)?.toDouble() ?? 0;
      if (sold <= 0) continue;
      fractions[saleId] = returned / sold;
    }
    return fractions;
  }

  /// Records a delivery: stock arriving, and what it cost.
  ///
  /// ## WHAT IT IS ONE TRANSACTION FOR
  ///
  /// The receipt, its lines, the stock movements, the cost history and the
  /// products' costs all move together, or none of them move. A delivery that
  /// put the stock on the shelf and then failed to record the cost would leave
  /// the shop selling at a margin it never agreed to.
  ///
  /// ## WHAT THE COST DOES
  ///
  /// The product's own cost becomes the cost THIS delivery paid, and the
  /// previous cost is kept in the history. That is the point of the feature:
  /// "today cost is a static field, so profit drifts from reality" — a bottle
  /// bought at 90 and a bottle bought at 110 are the same bottle and different
  /// money, and the profit on every later sale is measured against the price
  /// the shop actually paid.
  ///
  /// ## THE MARGIN IS NOT CHECKED HERE
  ///
  /// A line that arrives below the selling price is a decision, not a
  /// mistake, and the review before posting is where the owner sees it. This
  /// writes what it is told.
  Future<int> postStockReceipt({
    required List<StockReceiptLine> lines,
    int? supplierId,
    String? supplierRef,
    String? note,
    required String staffName,
    int? staffId,
    DateTime? receivedAt,
  }) async {
    if (lines.isEmpty) {
      throw StateError('A delivery must contain at least one line');
    }
    final db = await database;
    return db.transaction<int>((txn) async {
      final String now = (receivedAt ?? DateTime.now()).toIso8601String();
      int totalCost = 0;
      final List<({StockReceiptLine line, int oldCost, int newCost})> costs =
          <({StockReceiptLine line, int oldCost, int newCost})>[];

      for (final StockReceiptLine line in lines) {
        if (line.qty <= 0) {
          throw StateError('A received quantity must be more than zero');
        }
        final List<Map<String, Object?>> product = await txn.query(
          'products',
          columns: <String>['id', 'cost_price', 'stock_qty', 'track_variants'],
          where: 'id = ?',
          whereArgs: [line.productId],
          limit: 1,
        );
        if (product.isEmpty) {
          throw StateError('That product is not in the catalogue');
        }
        final int oldCost = (product.first['cost_price'] as num?)?.toInt() ?? 0;
        final int newCost = line.unitCost.minorUnits;
        final int lineCost = (newCost * line.qty).round();
        totalCost += lineCost;
        costs.add((line: line, oldCost: oldCost, newCost: newCost));

        // The stock, in the same transaction as the movement that describes
        // it — the same rule every other stock change in this app follows.
        final double balance = await _productBalanceAfter(txn, line.productId);
        await _writeStockMovement(
          txn,
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
        await _restoreStockCount(
          txn,
          productId: line.productId,
          variantId: line.variantId,
          units: line.qty,
        );
      }

      final int receiptId = await txn.insert('stock_receipts', {
        'supplier_id': supplierId,
        'supplier_ref': supplierRef,
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
          'unit_cost_minor': cost.newCost,
          'line_cost_minor': (cost.newCost * cost.line.qty).round(),
          'old_cost_minor': cost.oldCost,
          'new_cost_minor': cost.newCost,
        });
        // The history: how the cost got to be what it is.
        await txn.insert('product_cost_history', {
          'product_id': cost.line.productId,
          'variant_id': cost.line.variantId,
          'effective_at': now,
          'old_cost_minor': cost.oldCost,
          'new_cost_minor': cost.newCost,
          'reason': 'receipt',
          'receipt_id': receiptId,
        });
        // The product's cost is now the cost this delivery paid.
        await txn.rawUpdate(
          'UPDATE products SET cost_price = ?, updated_at = ? WHERE id = ?',
          <Object?>[cost.newCost, now, cost.line.productId],
        );
      }

      return receiptId;
    });
  }

  /// The deliveries, newest first.
  Future<List<StockReceipt>> getStockReceipts({int limit = 100}) async {
    final db = await database;
    final rows = await db.query(
      'stock_receipts',
      orderBy: 'received_at DESC, id DESC',
      limit: limit,
    );
    final receipts = <StockReceipt>[];
    for (final row in rows) {
      final itemRows = await db.query(
        'stock_receipt_items',
        where: 'receipt_id = ?',
        whereArgs: [row['id']],
        orderBy: 'id ASC',
      );
      receipts.add(
        StockReceipt.fromMap(row).let(
          (r) => StockReceipt(
            id: r.id,
            supplierId: r.supplierId,
            supplierRef: r.supplierRef,
            receivedAt: r.receivedAt,
            staffId: r.staffId,
            staffName: r.staffName,
            totalCost: r.totalCost,
            status: r.status,
            note: r.note,
            items: itemRows.map(StockReceiptItem.fromMap).toList(),
          ),
        ),
      );
    }
    return receipts;
  }

  /// The cost a product last arrived at, so the next delivery can be
  /// prefilled with it.
  ///
  /// The LAST delivery's cost, not the average and not the product's own
  /// field: the number the owner is about to replace is the number they last
  /// paid.
  Future<Money?> lastCostForProduct(int productId) async {
    final rows = await (await database).rawQuery(
      'SELECT new_cost_minor FROM product_cost_history '
      'WHERE product_id = ? ORDER BY effective_at DESC, id DESC LIMIT 1',
      [productId],
    );
    if (rows.isEmpty) return null;
    return Money.fromMinor(
        (rows.first['new_cost_minor'] as num?)?.toInt() ?? 0);
  }

  /// The suppliers, active ones first.
  Future<List<Supplier>> getSuppliers({bool activeOnly = true}) async {
    final rows = await (await database).query(
      'suppliers',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'name ASC',
    );
    return rows.map(Supplier.fromMap).toList();
  }

  /// Adds a supplier.
  ///
  /// The name is unique among the ACTIVE ones, case-insensitively: two
  /// suppliers called "Kentex" and "kentex" are one supplier, and a history
  /// that splits them is a history nobody can read.
  Future<int> addSupplier({
    required String name,
    String? phone,
    String? contactPerson,
    String? notes,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('A supplier needs a name');
    }
    final db = await database;
    final existing = await db.query(
      'suppliers',
      columns: <String>['id'],
      where: 'active = 1 AND LOWER(name) = ?',
      whereArgs: [trimmed.toLowerCase()],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw StateError('That supplier is already on the list');
    }
    return db.insert('suppliers', <String, Object?>{
      'name': trimmed,
      'phone': phone,
      'contact_person': contactPerson,
      'notes': notes,
      'active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// The deliveries the server has not seen yet.
  Future<List<StockReceipt>> getUnsyncedReceipts({int limit = 100}) async {
    final db = await database;
    final rows = await db.query(
      'stock_receipts',
      where: 'synced_to_backend = 0',
      orderBy: 'received_at ASC, id ASC',
      limit: limit,
    );
    final receipts = <StockReceipt>[];
    for (final row in rows) {
      final itemRows = await db.query(
        'stock_receipt_items',
        where: 'receipt_id = ?',
        whereArgs: [row['id']],
        orderBy: 'id ASC',
      );
      receipts.add(
        StockReceipt.fromMap(row).let(
          (r) => StockReceipt(
            id: r.id,
            supplierId: r.supplierId,
            supplierRef: r.supplierRef,
            receivedAt: r.receivedAt,
            staffId: r.staffId,
            staffName: r.staffName,
            totalCost: r.totalCost,
            status: r.status,
            note: r.note,
            items: itemRows.map(StockReceiptItem.fromMap).toList(),
          ),
        ),
      );
    }
    return receipts;
  }

  /// Marks these deliveries as pushed.
  Future<void> markReceiptsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.rawUpdate(
      'UPDATE stock_receipts SET synced_to_backend = 1 WHERE id IN '
      '(${List.filled(ids.length, '?').join(',')})',
      ids,
    );
  }

  /// The returns the server has not seen yet.
  Future<List<SaleReturn>> getUnsyncedReturns({int limit = 200}) async {
    final db = await database;
    final rows = await db.query(
      'sale_returns',
      where: 'synced_to_backend = 0',
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    final returns = <SaleReturn>[];
    for (final row in rows) {
      final itemRows = await db.query(
        'sale_return_items',
        where: 'return_id = ?',
        whereArgs: [row['id']],
        orderBy: 'id ASC',
      );
      returns.add(
        SaleReturn.fromMap(row).let(
          (r) => SaleReturn(
            id: r.id,
            saleId: r.saleId,
            kind: r.kind,
            reason: r.reason,
            total: r.total,
            vatTotal: r.vatTotal,
            profit: r.profit,
            refundMethod: r.refundMethod,
            paymentReference: r.paymentReference,
            staffId: r.staffId,
            staffName: r.staffName,
            createdAt: r.createdAt,
            items: itemRows.map(SaleReturnItem.fromMap).toList(),
          ),
        ),
      );
    }
    return returns;
  }

  /// Marks these returns as pushed.
  Future<void> markReturnsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.rawUpdate(
      'UPDATE sale_returns SET synced_to_backend = 1 WHERE id IN '
      '(${List.filled(ids.length, '?').join(',')})',
      ids,
    );
  }

  Future<List<Sale>> getSalesAfter(DateTime? after,
      {required int limit}) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];
    if (after != null) {
      where.add('created_at > ?');
      args.add(after.toIso8601String());
    }
    final rows = await db.query(
      'sales',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    if (rows.isEmpty) return [];
    Map<dynamic, List<Map<String, dynamic>>> itemsBySale =
        <dynamic, List<Map<String, dynamic>>>{};
    final saleIds = rows.map((row) => row['id']).toList();
    final itemRows = await db.query(
      'sale_items',
      where: 'sale_id IN (${List.filled(saleIds.length, '?').join(',')})',
      whereArgs: saleIds,
    );
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
    // Midnight arithmetic, NOT `+ Duration(days: 1)`.
    //
    // A day is not always 24 hours: in a timezone with daylight saving, the
    // day the clocks go forward is 23 hours long and the day they go back is
    // 25. Adding a day to local midnight lands on 01:00 or 23:00 of the
    // neighbouring day, and the loop then skips a day or visits one twice —
    // so the chart shows a day twice, or not at all, exactly twice a year.
    //
    // Kenya has no daylight saving, so this changes nothing here. It changes
    // everything the day this app is sold in a place that does.
    final until = DateTime(today.year, today.month, today.day + 1);
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
        cursor = DateTime(cursor.year, cursor.month, cursor.day + 1)) {
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
  /// against the payment provider, and confirms it here. [reference] replaces
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

    // MINUS the cash that was given back out of THIS drawer.
    //
    // A cash refund takes money out of the drawer that is open when the
    // return happens — not the drawer the sale was rung in, which was closed
    // hours ago. So the return names the drawer it emptied, and that drawer
    // is the one whose expected cash falls.
    //
    // Without this the drawer would be judged against money that had already
    // gone out of it, and every refund would look like a shortage of exactly
    // the amount refunded.
    final refunds = await (await database).rawQuery(
      '''SELECT COALESCE(SUM(total), 0) AS total_minor
         FROM sale_returns
         WHERE shift_id = ?
           AND refund_method = 'cash' ''',
      [shift.id],
    );
    final refunded = (refunds.first['total_minor'] as num?)?.toInt() ?? 0;

    return Money.fromMinor(minor - refunded);
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
    // A capacity of ZERO means "the size is not known", which is allowed.
    //
    // A shot cup is a NAME for a serving — "Single", "Double", "One shot" —
    // and the size in millilitres is the owner's business, not the app's. It
    // is what lets the app work out the cost of one shot exactly, so a cup
    // with a size earns its cost and a cup without one is counted as profit
    // the whole way through.
    //
    // A NEGATIVE capacity is still a mistake and is still refused: a cup of
    // minus thirty millilitres is not a serving.
    if (cup.capacityMl < 0) {
      throw StateError('A shot cup cannot have a negative size');
    }
    final exists = await db.query('products',
        columns: ['id'], where: 'id = ?', whereArgs: [cup.productId], limit: 1);
    if (exists.isEmpty) {
      throw StateError(
          'Shot cup product ${cup.productId} does not exist in the catalogue');
    }
    // A cup exists only because something can be poured from it, so the
    // product must be volumetric. Derive the unit instead of asking: a product
    // that was once "each" becomes "ml" the moment its first cup is saved.
    return db.transaction((txn) async {
      final row = await txn.query('products',
          columns: ['unit'],
          where: 'id = ?',
          whereArgs: [cup.productId],
          limit: 1);
      final currentUnit = row.isNotEmpty ? row.first['unit'] as String? : null;
      if (currentUnit == ProductUnit.each.wire) {
        await txn.update('products', {'unit': ProductUnit.millilitre.wire},
            where: 'id = ?', whereArgs: [cup.productId]);
      }
      if (cup.id == null) {
        return txn.insert('shot_cups', cup.toMap()..remove('id'));
      }
      await txn.update('shot_cups', cup.toMap(),
          where: 'id = ?', whereArgs: [cup.id]);
      return cup.id!;
    });
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
  // -------------------------------------------------------------------------
  // The audit log
  //
  // Every state-changing action in the app writes exactly one row, through
  // exactly one method, so "who did what" cannot silently stop being recorded
  // because a call site forgot to. The method is `recordAudit`; a screen never
  // INSERTs into `audit_log` itself.
  // -------------------------------------------------------------------------

  /// Writes one audit row.
  ///
  /// Returns the new row's id so a caller can chain it onto the action it
  /// recorded (the inventory screen does this: the row it writes is then
  /// selectable as "this is the product I just changed").
  ///
  /// The row is written and the log is trimmed in ONE transaction, so the
  /// table the trim bounds is bounded by the very write that extends it — a
  /// separate `pruneAuditLog` an unbounded number of call sites must remember
  /// to invoke is how an audit log grows forever on a busy till.
  Future<int> recordAudit(AuditLogEntry entry) async {
    final db = await database;
    return db.transaction((txn) async {
      final id = await txn.insert('audit_log', entry.toMap());
      await _trimAuditLog(txn);
      return id;
    });
  }

  /// Writes several audit rows that belong to one action, in one transaction.
  ///
  /// The variant/barcode save on the inventory screen is the reason this
  /// exists: that action is one transaction for its data but then fired four
  /// separate audit transactions, which is four disk commits — and four fsyncs
  /// on the sale path — for one user-visible gesture.
  Future<void> recordAudits(List<AuditLogEntry> entries) async {
    if (entries.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in entries) {
        batch.insert('audit_log', entry.toMap());
      }
      await batch.commit(noResult: true);
      await _trimAuditLog(txn);
    });
  }

  /// Deletes rows past the newest [auditRetainRows], only when there are any.
  ///
  /// Runs inside the writing transaction, so the cap can never be observed
  /// above the limit by another reader.
  ///
  /// Cut on `(created_at, id)` — the same key every READER orders by — rather
  /// than on `id` alone. The id-only form was cheaper and wrong: `created_at`
  /// comes from the device clock, so a phone whose clock moved backwards gives
  /// older rows later timestamps, and the id cut then deleted the newest work
  /// and kept the stale. An audit log exists to answer "who changed what
  /// recently", so dropping the recent rows is a defect on the feature's whole
  /// surface.
  ///
  /// The delete compares the timestamp FIRST and breaks ties on id, which is
  /// what "older than the boundary row" means under the readers' ordering. A
  /// bare `id < boundary` would be wrong in the same way the id-only cut was:
  /// the boundary row often has a LOWER id than rows it is newer than, and the
  /// comparison would then delete nothing.
  ///
  /// The COUNT-then-cut shape keeps the cost down: when the table is already
  /// under the cap it does nothing at all, and otherwise it is one indexed
  /// lookup (`idx_audit_created`) plus a delete over that range.
  Future<void> _trimAuditLog(Transaction txn) async {
    final rows = await txn
        .rawQuery('SELECT COUNT(*) AS total FROM audit_log', <Object?>[]);
    final total = rows.isEmpty ? 0 : rows.first['total'] as int? ?? 0;
    if (total <= auditRetainRows) return;
    // The boundary row, in the order the readers use: everything older than it
    // goes.
    final boundary = await txn.rawQuery(
      'SELECT id, created_at FROM audit_log '
      'ORDER BY created_at DESC, id DESC LIMIT 1 OFFSET ?',
      <Object?>[auditRetainRows - 1],
    );
    if (boundary.isEmpty) return;
    final boundaryRow = boundary.first;
    final cutoffAt = boundaryRow['created_at'] as String?;
    final cutoffId = boundaryRow['id'] as int?;
    if (cutoffAt == null || cutoffId == null) return;
    await txn.delete(
      'audit_log',
      where: 'created_at < ? OR (created_at = ? AND id < ?)',
      whereArgs: <Object?>[cutoffAt, cutoffAt, cutoffId],
    );
  }

  /// Every row on one entity, newest first.
  ///
  /// The "what happened to this product" question, which is the one the
  /// inventory screen asks when an owner taps an audit badge.
  Future<List<AuditLogEntry>> auditForEntity(
    AuditEntity entity,
    String entityId, {
    int limit = 100,
  }) async {
    return auditLog(AuditLogQuery(
      entity: entity,
      entityId: entityId,
      limit: limit,
    ));
  }

  /// A filtered window of the log, newest first.
  ///
  /// One method for the admin dashboard and for the in-app activity view, so a
  /// filter added to one is not missing from the other.
  Future<List<AuditLogEntry>> auditLog(AuditLogQuery query) async {
    final db = await database;
    final conditions = <String>[];
    final args = <Object?>[];

    if (query.entity != null) {
      conditions.add('entity = ?');
      args.add(query.entity!.wire);
    }
    if (query.entityId != null) {
      conditions.add('entity_id = ?');
      args.add(query.entityId);
    }
    if (query.actorId != null) {
      conditions.add('actor_id = ?');
      args.add(query.actorId);
    }
    if (query.actions != null && query.actions!.isNotEmpty) {
      final placeholders =
          List<String>.filled(query.actions!.length, '?').join(', ');
      conditions.add('action IN ($placeholders)');
      args.addAll(query.actions!.map((a) => a.wire));
    }
    if (query.since != null) {
      conditions.add('created_at >= ?');
      args.add(query.since);
    }

    final rows = await db.query(
      'audit_log',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: conditions.isEmpty ? null : args,
      orderBy: 'created_at DESC, id DESC',
      limit: query.limit,
    );
    return rows.map(AuditLogEntry.fromMap).toList();
  }

  /// The rows an owner's activity view opens on: the actions that change what
  /// the shop can do, rather than the thousands of sale rows.
  static const List<AuditAction> _ownerVisibleActions = <AuditAction>[
    AuditAction.staffAdded,
    AuditAction.staffRemoved,
    AuditAction.staffPinReset,
    AuditAction.productVariantRemoved,
    AuditAction.barcodeRemoved,
    AuditAction.barcodeKindChanged,
    AuditAction.taxSettingsChanged,
    AuditAction.paymentMethodChanged,
    AuditAction.printerSaved,
    AuditAction.backupErased,
    AuditAction.backupRestored,
    AuditAction.shopCreated,
    AuditAction.shopSwitched,
    AuditAction.identityLinked,
  ];

  /// The control-relevant rows only.
  ///
  /// A raw activity feed is 200 sale rows deep before the manager's settings
  /// change that the owner actually wanted to see, so the owner's view reads a
  /// filtered list and the full log stays available for the admin dashboard.
  Future<List<AuditLogEntry>> ownerRelevantAudit({int limit = 50}) async {
    final db = await database;
    final placeholders =
        List<String>.filled(_ownerVisibleActions.length, '?').join(', ');
    final rows = await db.query(
      'audit_log',
      where: 'action IN ($placeholders)',
      whereArgs: _ownerVisibleActions.map((a) => a.wire).toList(),
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(AuditLogEntry.fromMap).toList();
  }

  /// How many audit rows a shop keeps.
  ///
  /// Every sale adds a row, so on a busy till this is what bounds the table:
  /// 5,000 rows is months of "who did what" on one shop and tens of kilobytes,
  /// and the admin dashboard is where longer history lives.
  static const int auditRetainRows = 5000;

  /// Trims the log to [keepRows].
  ///
  /// Kept as an explicit operation — the diagnostics screen and tests use it to
  /// force the state a capped log is meant to be in — but production writes go
  /// through [recordAudit] and [recordAudits], which trim in the same
  /// transaction as the insert. The cap is enforced by the write, not by a
  /// schedule something might forget to run.
  Future<int> pruneAuditLog({int keepRows = auditRetainRows}) async {
    final db = await database;
    return db.transaction((txn) async {
      final oldest = await txn.query('audit_log',
          columns: <String>['COUNT(*) as total'], limit: 1);
      if (oldest.isEmpty) return 0;
      final total = oldest.first['total'] as int;
      if (total <= keepRows) return 0;
      final cutoff = await txn.query('audit_log',
          columns: <String>['id'],
          orderBy: 'id DESC',
          offset: keepRows,
          limit: 1);
      if (cutoff.isEmpty) return 0;
      final cutoffId = cutoff.first['id'] as int;
      return txn.delete('audit_log',
          where: 'id <= ?', whereArgs: <Object?>[cutoffId]);
    });
  }

  /// How many rows the audit log holds.
  ///
  /// Reported so a shop can see that the log is capped rather than that it has
  /// quietly stopped recording. The cap is enforced by the writes, so this is
  /// a reading, not a control.
  Future<int> auditLogCount() async {
    final db = await database;
    final rows = await db.query('audit_log',
        columns: <String>['COUNT(*) as n'], limit: 1);
    if (rows.isEmpty) return 0;
    return rows.first['n'] as int;
  }

  // --------------------------------------------------------------- failure log

  /// How many failures a phone keeps.
  ///
  /// 200 is a fortnight of a genuinely broken build (a crash that happens on
  /// every sale), and under a megabyte of the text that matters — where a cap
  /// of 10,000 would be a phone whose storage a bug could eat.
  static const int crashRetainRows = 200;

  /// Records a failure and trims the log to [crashRetainRows] in the same
  /// transaction.
  ///
  /// The trim is INSIDE the write because "auto-deleting bounded logs" is a
  /// property of the write, not of a background job: a shop that never opens
  /// the diagnostics screen must not accumulate an unbounded log, and a job
  /// that runs "later" does not run on a phone that is switched off. Deleting
  /// the oldest is the cost — a fortnight of history is as far back as a
  /// phone's own failure log is useful anyway, and the admin dashboard is
  /// where long history lives.
  Future<int> recordCrash(CrashLogEntry entry) async {
    final db = await database;
    return db.transaction((txn) async {
      final id = await txn.insert('crash_log', entry.toMap());
      await _trimCrashLog(txn);
      return id;
    });
  }

  /// Deletes everything past the newest [crashRetainRows].
  ///
  /// Takes a transaction so the recorder's write cannot insert without it, and
  /// so the diagnostics screen's "clear" can reuse it.
  Future<void> _trimCrashLog(Transaction txn) async {
    final cutoff = await txn.query('crash_log',
        columns: <String>['id'],
        orderBy: 'id DESC',
        offset: crashRetainRows,
        limit: 1);
    if (cutoff.isEmpty) return;
    final cutoffId = cutoff.first['id'] as int;
    // `<=` and not `<`: the row the offset lands on IS the one being dropped,
    // and excluding it leaves the table one row over its cap on every write —
    // the difference between a bounded log and one that grows by one each time
    // the limit is reached.
    await txn
        .delete('crash_log', where: 'id <= ?', whereArgs: <Object>[cutoffId]);
  }

  /// The failure log, newest first.
  Future<List<CrashLogEntry>> crashLog(CrashLogQuery query) async {
    final db = await database;
    final conditions = <String>[];
    final args = <Object?>[];
    if (query.kinds != null && query.kinds!.isNotEmpty) {
      conditions.add('kind IN (${query.kinds!.map((_) => '?').join(', ')})');
      args.addAll(query.kinds!.map((kind) => kind.wire));
    }
    if (query.since != null) {
      conditions.add('created_at >= ?');
      args.add(query.since!);
    }
    final rows = await db.query(
      'crash_log',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC, id DESC',
      limit: query.limit,
    );
    return rows.map(CrashLogEntry.fromMap).toList(growable: false);
  }

  Future<int> crashLogCount() async {
    final db = await database;
    final rows = await db.query('crash_log',
        columns: <String>['COUNT(*) as n'], limit: 1);
    if (rows.isEmpty) return 0;
    return rows.first['n'] as int;
  }

  /// Empties the failure log. The owner's call, from the diagnostics screen,
  /// once a problem has been dealt with — keeping the log is otherwise right.
  Future<int> clearCrashLog() async {
    final db = await database;
    return db.delete('crash_log');
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
}

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

/// A one-holder gate for asynchronous work.
///
/// Not a general mutex — the app has no threads to protect anything from. It
/// covers the one case where two `async` operations sharing process state must
/// not interleave: moving the database to another shop. Without it, a tour that
/// walks every shop on the device can be interrupted by the owner switching
/// shops, or can interrupt an automatic sync, and either way the till ends up
/// pointed at a shop neither party chose.
///
/// Queue order is FIFO: each body runs to completion before the next starts,
/// and a body that throws does not poison the queue — the next waiter still
/// runs, and receives that body's error.
class _AsyncGate {
  Future<void> _drain = Future<void>.value();

  /// Runs [body], waiting for anything already queued.
  Future<T> run<T>(Future<T> Function() body) {
    final result = Completer<T>();
    _drain = _drain.then((_) async {
      try {
        result.complete(await body());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }
}

/// A line's fraction of its container. [containerMl] is the product's own
/// bottle/keg size, which only a measured pour needs.
///
/// A measured pour is capped at one whole container: a capacity typed larger
/// than the bottle it is poured from is a mistake in the shop's configuration,
/// and the least wrong answer to it is to empty that bottle rather than to
/// drive stock negative.
///
/// A measured pour with NO size takes nothing that can be measured. The old
/// answer was a whole container, which came from the days when a shot always
/// had a size: a shot of 30 ml out of a 750 ml bottle, and anything unreadable
/// was a whole bottle. With the size now optional, "unreadable" means the
/// owner did not say how big the shot is — and taking the whole bottle for it
/// would empty the shelf after one shot.
double _portionFactor(SaleItem item, double containerMl) {
  if (item.portion == SalePortion.half) return 0.5;
  if (item.portion == SalePortion.quarter) return 0.25;
  if (item.portion == SalePortion.measured) {
    if (item.portionMl <= 0) return 0.0;
    if (containerMl <= 0) return 1.0;
    final double fraction = item.portionMl / containerMl;
    return fraction > 1 ? 1.0 : fraction;
  }
  return 1.0;
}
