import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/audit_log.dart';
import '../models/crash_log.dart';
import '../models/credit.dart';
import '../models/financial_event.dart';
import '../models/models.dart';
import '../models/notification.dart';
import '../models/stock_movement.dart';
import '../models/product_pack.dart';
import '../models/incoming_payment.dart';
import '../models/layby.dart';
import '../utils/crypto_utils.dart';
import '../utils/money.dart';
import '../utils/units.dart';
// The aggregate result types (DailyTotals, ProductSalesRow, TimeBucket,
// DateBucket, PaymentMixRow, AttentionSummary). They live in services/ rather
// than here so this file stays a data layer: it produces rows, it does not
// define what a chart or a screen does with them.
import '../services/analytics.dart';
import '../services/product_image_store.dart';
import '../services/workspace_service.dart';
import '../services/roles.dart';
import '../profile/shop_profile.dart';

class _SnapshotMediaRollback {
  const _SnapshotMediaRollback(this.oldBytes, {this.documents});

  final Map<String, List<int>?> oldBytes;
  final Directory? documents;

  Future<void> rollback() async {
    final docs = documents;
    if (docs == null) return;
    for (final entry in oldBytes.entries) {
      final file = File(join(docs.path, entry.key));
      final bytes = entry.value;
      if (bytes == null) {
        if (await file.exists()) await file.delete();
      } else {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      }
    }
  }
}

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
  int _databaseGeneration = 0;

  /// Whether advisory background work may use the current database handle.
  ///
  /// Sign-in can outlive a widget test's database teardown, so callers that
  /// launch non-critical work must not reopen or touch storage after a reset.
  bool get hasOpenDatabase => _db != null;

  /// Serialises moving this singleton to another shop.
  ///
  /// Held for a whole operation, not for a single switch, so that a caller
  /// which must walk several shops (the cross-shop activity read) can keep the
  /// database still for as long as it is looking.
  static final _AsyncGate _workspaceGate = _AsyncGate();
  static Future<void>? _pendingTestClose;

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
    _databaseGeneration++;
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
    while (true) {
      final existing = _db;
      if (existing != null) return existing;
      final generation = _databaseGeneration;
      final opened = await _initDb();
      // A reset or workspace switch may have happened while the filesystem
      // database was opening. Never let that stale future replace the newer
      // handle (especially a test's isolated in-memory handle).
      if (generation != _databaseGeneration) {
        await opened.close();
        continue;
      }
      final current = _db;
      if (current != null) {
        await opened.close();
        return current;
      }
      _db = opened;
      _pendingTestClose = null;
      return opened;
    }
  }

  /// Test-only: Reset the singleton instance for test isolation
  @visibleForTesting
  static void resetForTests() {
    final Database? previous = instance._db;
    instance._db = null;
    instance._databaseGeneration++;
    // The database handle and its workspace pointer are one piece of test
    // state. A preceding multi-shop test may have left the singleton pointed
    // at another workspace; the next in-memory database must start from the
    // same default context as a fresh process.
    instance._workspaceKey = 'legacy';
    // sqflite's close is asynchronous. Test files deliberately reset and
    // reopen the singleton between cases; leaving the old in-memory handle
    // closing in the background lets a later case race the new handle.
    _pendingTestClose = previous?.close();
  }

  /// Bump this every time the schema changes, and add the matching branch in
  /// [_onUpgrade]. Never edit an already-released migration after it has
  /// shipped — always add a new one, even for a one-line fix — because a
  /// shop's phone may be several versions behind and needs every step run
  /// in order to land on the current schema without data loss.
  static const _schemaVersion = 75;

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
  static const String settingMpesaChannelId = 'mpesa_payhero_channel_id';
  static const String settingMpesaChannelType = 'mpesa_payhero_channel_type';
  static const String settingMpesaMerchantNumber = 'mpesa_merchant_number';
  static const String settingTin = 'tin';
  static const String settingEtimsDeviceId = 'etims_device_id';
  static const String settingCashDrawerEnabled = 'cash_drawer_enabled';
  static const String settingCashDrawerOnCashSale =
      'cash_drawer_open_on_cash_sale';
  static const String settingCashDrawerPin = 'cash_drawer_pin';
  static const String settingCashDrawerOnMs = 'cash_drawer_pulse_on_ms';
  static const String settingCashDrawerOffMs = 'cash_drawer_pulse_off_ms';
  static const String settingExpenseApprovalLimitMinor =
      'expense_approval_limit_minor';
  static const String settingTaxRuleId = 'tax_rule_id';
  static const String settingTaxRuleVersion = 'tax_rule_version';

  // Credit (v30). Selling on account is a deliberate, money-adjacent
  // capability, so it ships OFF and the owner turns it on (spec D5).
  static const String settingCreditEnabled = 'credit_enabled';
  static const String settingCreditDefaultLimitMinor =
      'credit_default_limit_minor';

  /// `warn` or `block`: what happens when a sale would put a customer past
  /// their limit. A manager approval overrides a block; a warn never stops
  /// the sale.
  static const String settingCreditLimitMode = 'credit_limit_mode';
  static const String settingCreditCashiersAllowed = 'credit_cashiers_allowed';
  static const String settingCreditReminderTemplate =
      'credit_reminder_template';

  // Discounts are deliberately disabled until the owner enables them.
  static const String settingDiscountsEnabled = 'discounts_enabled';
  static const String settingCashierDiscountPercent =
      'discount_cashier_percent';
  static const String settingManagerDiscountPercent =
      'discount_manager_percent';
  static const String settingDiscountReasonRequired =
      'discount_reason_required';
  static const String settingDiscountBelowCostAllowed =
      'discount_below_cost_allowed';

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

  /// Deletes one failed workspace database after its registry entry has been
  /// removed. The target is an exact workspace-derived path; broad database
  /// deletion is deliberately not exposed.
  static Future<void> deleteWorkspace(String workspaceKey) async {
    if (workspaceKey.trim().isEmpty || workspaceKey == 'legacy') return;
    await _workspaceGate.run(() async {
      if (instance._workspaceKey == workspaceKey && instance._db != null) {
        await instance._db!.close();
        instance._db = null;
      }
      await databaseFactory.deleteDatabase(await databasePathFor(workspaceKey));
    });
  }

  /// Test-only: a fresh, isolated in-memory instance with the real schema,
  /// bypassing getDatabasesPath() (which needs a platform channel that
  /// doesn't exist in a plain `flutter test` run). Pair with
  /// sqflite_common_ffi's databaseFactoryFfi in test setUp — see
  /// test/database_helper_test.dart for the exact pattern.
  @visibleForTesting
  static Future<DatabaseHelper> openInMemoryForTests() async {
    await _pendingTestClose;
    _pendingTestClose = null;
    // A preceding workspace test may still have a switch queued on the
    // singleton gate. Do not install a fresh in-memory handle until that work
    // has finished, otherwise the queued switch can close or repoint the new
    // handle during the next test.
    await _workspaceGate.run(() async {});
    instance._workspaceKey = 'legacy';
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
    if (oldVersion < 66) {
      await _createShopProfileTable(db);
    }
    if (oldVersion < 67) {
      await _createFinancialEventTable(db);
    }
    if (oldVersion < 68) {
      await _createOwnerTransactionsTable(db);
    }
    if (oldVersion < 69) {
      await _createOpenFinanceTables(db);
    }
    if (oldVersion < 70) {
      await _addColumnIfMissing(
        db,
        'financial_events',
        'customer_deposit_delta_minor',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 71) {
      await _createExpensePaymentsTable(db);
    }
    if (oldVersion < 72) {
      await _ensureTaxRuleSnapshotColumns(db);
    }
    if (oldVersion < 73) {
      await _ensurePurchaseTaxEvidenceColumns(db);
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
    if (oldVersion < 57) {
      await _addColumnIfMissing(
        db,
        'expenses',
        'approved_by',
        'INTEGER',
      );
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
    if (oldVersion < 30) {
      await _migrateCustomers(db);
      await _migrateRestockDraft(db);
    }
    if (oldVersion < 31) await _migrateExpenses(db);
    if (oldVersion < 32) await _migrateDiscounts(db);
    if (oldVersion < 33) await _migrateSplitPaymentPending(db);
    if (oldVersion < 34) await _migrateHeldCarts(db);
    if (oldVersion < 35) await _migrateReceiptShares(db);
    if (oldVersion < 36) await _migrateCashDrawer(db);
    if (oldVersion < 37) await _migrateStocktake(db);
    if (oldVersion < 38) await _migrateBackupLog(db);
    if (oldVersion < 39) await _migrateProductPacks(db);
    if (oldVersion < 40) await _migrateReordering(db);
    if (oldVersion < 41) await _migratePackHeldLines(db);
    if (oldVersion < 42) await _migrateIncomingPayments(db);
    if (oldVersion < 43) await _migrateHeldCustomer(db);
    if (oldVersion < 44) await _migratePermissions(db);
    if (oldVersion < 45) await _migrateExpiryBatches(db);
    if (oldVersion < 46) await _migrateShiftReports(db);
    if (oldVersion < 47) await _migrateOperationalLedgerSync(db);
    if (oldVersion < 48) await _migrateStockMovementSync(db);
    if (oldVersion < 49) await _migrateRemoteOperationalRecords(db);
    if (oldVersion < 50) await _migrateDrawerEventSync(db);
    if (oldVersion < 51) await _migrateSyncConflicts(db);
    if (oldVersion < 52) await _migrateSaleBuyerSnapshot(db);
    if (oldVersion < 53) await _migrateReturnRefundAllocations(db);
    if (oldVersion < 54) await _migrateIncomingPaymentClaims(db);
    if (oldVersion < 55) await _migrateReorderingSync(db);
    if (oldVersion < 56) await _migrateProductPriceHistory(db);
    if (oldVersion < 58) await _migrateCashDrawerMetadata(db);
    if (oldVersion < 59) await _migrateStocktakeMetadata(db);
    if (oldVersion < 60) await _migrateProductPackVariants(db);
    if (oldVersion < 61) await _migrateLabelPrintJobs(db);
    if (oldVersion < 62) await _migrateExpiryBatchMetadata(db);
    if (oldVersion < 63) await _migrateExpiryReceiptMetadata(db);
    if (oldVersion < 64) await _migratePermissionModes(db);
    if (oldVersion < 65) await _migrateNotifications(db);
    if (oldVersion < 74) await _migrateLaybys(db);
    if (oldVersion < 75) await _migrateExchanges(db);
  }

  Future<void> _migrateNotifications(Database db) async {
    await _createNotificationTables(db);
  }

  /// v74: Fashion reservations and lay-by deposits.
  ///
  /// Reservations live beside the on-hand balance rather than pretending that
  /// goods left the shop when a customer only paid a deposit. This lets normal
  /// checkout subtract open lay-by quantities from available stock while the
  /// financial event stream records deposits as liabilities until completion.
  Future<void> _migrateLaybys(Database db) async {
    await _createLaybyTables(db);
    await _addColumnIfMissing(
        db, 'products', 'reserved_qty', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'product_variants', 'reserved_qty', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'layby_payments', 'direction', "TEXT NOT NULL DEFAULT 'in'");
  }

  Future<void> _createLaybyTables(Database db) async {
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
  }

  /// v75: a replacement sale and its return are one exchange document.
  Future<void> _migrateExchanges(Database db) async {
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_exchanges_original_sale '
        'ON exchanges (original_sale_id, created_at)');
  }

  Future<void> _createNotificationTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS notification_prefs (
      staff_id INTEGER NOT NULL,
      type TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1,
      quiet_start INTEGER,
      quiet_end INTEGER,
      PRIMARY KEY (staff_id, type)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS notification_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      staff_id INTEGER NOT NULL,
      type TEXT NOT NULL,
      dedupe_key TEXT NOT NULL,
      count INTEGER NOT NULL,
      fired_at TEXT NOT NULL,
      opened_at TEXT
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_notification_log_lookup '
        'ON notification_log (staff_id, type, dedupe_key, fired_at DESC)');
  }

  Future<void> _migratePermissionModes(Database db) async {
    final roleTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'role_permissions'");
    if (roleTable.isEmpty) return;
    await _addColumnIfMissing(
        db, 'role_permissions', 'mode', "TEXT NOT NULL DEFAULT 'deny'");
    await _addColumnIfMissing(db, 'staff_permission_overrides', 'mode',
        "TEXT NOT NULL DEFAULT 'deny'");
    await db.rawUpdate(
        "UPDATE role_permissions SET mode = CASE WHEN allowed = 1 THEN 'allow' ELSE 'deny' END WHERE mode = 'deny' AND allowed = 1");
    await db.rawUpdate(
        "UPDATE staff_permission_overrides SET mode = CASE WHEN allowed = 1 THEN 'allow' ELSE 'deny' END WHERE mode = 'deny' AND allowed = 1");
    await _seedPermissionDefaults(db);
  }

  Future<void> _migrateExpiryReceiptMetadata(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'stock_receipt_items'");
    if (tables.isEmpty) return;
    await _addColumnIfMissing(db, 'stock_receipt_items', 'expiry_date', 'TEXT');
    await _addColumnIfMissing(db, 'stock_receipt_items', 'batch_code', 'TEXT');
  }

  Future<void> _migrateExpiryBatchMetadata(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'stock_batches'");
    // Some historical repair fixtures have no expiry tables at all and reach
    // the current version through a later upgrade path. The v45 migration (or
    // a fresh install) owns creation; v62 must not create an index against a
    // table that is intentionally absent in that legacy fixture.
    if (tables.isEmpty) return;
    await _addColumnIfMissing(db, 'stock_batches', 'variant_id', 'INTEGER');
    await _addColumnIfMissing(db, 'stock_batches', 'batch_code', 'TEXT');
    await _addColumnIfMissing(
        db, 'stock_batches', 'status', "TEXT NOT NULL DEFAULT 'active'");
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_batches_variant '
        'ON stock_batches (product_id, variant_id, expires_at, id)');
  }

  Future<void> _migrateProductPriceHistory(Database db) async {
    await _createProductPriceHistoryTable(db);
  }

  Future<void> _createProductPriceHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_price_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        recorded_at TEXT NOT NULL,
        cost_price INTEGER NOT NULL,
        sell_price INTEGER NOT NULL,
        reason TEXT,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_product_price_history_product_time '
        'ON product_price_history (product_id, recorded_at DESC, id DESC)');
  }

  Future<void> _migrateSaleBuyerSnapshot(Database db) async {
    await _addColumnIfMissing(db, 'sales', 'buyer_name', 'TEXT');
    await _addColumnIfMissing(db, 'sales', 'buyer_tin', 'TEXT');
  }

  Future<void> _migrateReturnRefundAllocations(Database db) async {
    await _createReturnRefundAllocationsTable(db);
  }

  Future<void> _migrateIncomingPaymentClaims(Database db) async {
    await _createIncomingPaymentClaimsTable(db);
  }

  Future<void> _migrateReorderingSync(Database db) async {
    await _addColumnIfMissing(
        db, 'suppliers', 'synced_to_backend', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, 'product_suppliers', 'synced_to_backend',
        'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, 'purchase_orders', 'synced_to_backend',
        'INTEGER NOT NULL DEFAULT 0');
  }

  Future<void> _migrateDrawerEventSync(Database db) async {
    await _addColumnIfMissing(
      db,
      'drawer_events',
      'synced_to_backend',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _migrateCashDrawerMetadata(Database db) async {
    await _addColumnIfMissing(db, 'drawer_events', 'sale_id', 'INTEGER');
    await _addColumnIfMissing(db, 'drawer_events', 'approved_by', 'TEXT');
    await _addColumnIfMissing(
        db, 'drawer_events', 'success', 'INTEGER NOT NULL DEFAULT 0');
  }

  Future<void> _migrateStocktakeMetadata(Database db) async {
    await _addColumnIfMissing(db, 'stock_counts', 'name', 'TEXT');
    await _addColumnIfMissing(
        db, 'stock_counts', 'scope_type', "TEXT NOT NULL DEFAULT 'all'");
    await _addColumnIfMissing(db, 'stock_counts', 'scope_ref', 'TEXT');
    await _addColumnIfMissing(db, 'stock_counts', 'sales_mode',
        "TEXT NOT NULL DEFAULT 'keep_selling'");
    await _addColumnIfMissing(db, 'stock_counts', 'applied_at', 'TEXT');
    await _addColumnIfMissing(db, 'stock_counts', 'applied_by', 'INTEGER');
    await _addColumnIfMissing(db, 'stock_counts', 'note', 'TEXT');
    await _addColumnIfMissing(db, 'stock_count_lines', 'counted_by', 'INTEGER');
    await _addColumnIfMissing(db, 'stock_count_lines', 'note', 'TEXT');
  }

  Future<void> _migrateProductPackVariants(Database db) async {
    await _addColumnIfMissing(db, 'product_packs', 'variant_id', 'INTEGER');
  }

  Future<void> _migrateLabelPrintJobs(Database db) async {
    await _createLabelPrintJobsTable(db);
  }

  Future<void> _createLabelPrintJobsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS label_print_jobs (
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
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_label_print_jobs_status ON label_print_jobs (status, updated_at DESC)');
  }

  Future<void> _migrateSyncConflicts(Database db) async {
    await _createSyncConflictsTable(db);
  }

  Future<void> _createSyncConflictsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        local_id INTEGER,
        device_id TEXT,
        reason TEXT NOT NULL,
        payload_json TEXT,
        created_at TEXT NOT NULL,
        resolved_at TEXT,
        resolution TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_conflicts_open '
        'ON sync_conflicts (resolved_at, created_at DESC)');
  }

  Future<void> _migrateOperationalLedgerSync(Database db) async {
    for (final table in <String>['expenses', 'till_movements']) {
      await _addColumnIfMissing(
        db,
        table,
        'synced_to_backend',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> _migrateStockMovementSync(Database db) async {
    await _addColumnIfMissing(
      db,
      'stock_movements',
      'synced_to_backend',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _migrateRemoteOperationalRecords(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS remote_operational_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        remote_id TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        device_id TEXT,
        local_id INTEGER,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_remote_operational_kind ON remote_operational_records (kind, updated_at DESC)');
  }

  Future<void> _migratePermissions(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS role_permissions (
        role TEXT NOT NULL,
        permission TEXT NOT NULL,
        allowed INTEGER NOT NULL DEFAULT 0,
        mode TEXT NOT NULL DEFAULT 'deny',
        PRIMARY KEY (role, permission)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff_permission_overrides (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staff_id INTEGER NOT NULL,
        permission TEXT NOT NULL,
        allowed INTEGER NOT NULL,
        mode TEXT NOT NULL DEFAULT 'deny',
        UNIQUE(staff_id, permission)
      )
    ''');
    await _seedPermissionDefaults(db);
  }

  /// Expiry is additive. Existing stock remains ordinary stock until the owner
  /// enables tracking; only dated receipts create batches.
  Future<void> _migrateExpiryBatches(Database db) async {
    await _addColumnIfMissing(
        db, 'products', 'track_expiry', 'INTEGER NOT NULL DEFAULT 0');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        product_id INTEGER NOT NULL,
        variant_id INTEGER,
        batch_code TEXT,
        receipt_id INTEGER,
        received_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        qty_remaining REAL NOT NULL,
        unit_cost_minor INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'active',
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_item_batches (
        sale_item_id INTEGER NOT NULL,
        batch_id INTEGER NOT NULL,
        qty REAL NOT NULL,
        PRIMARY KEY (sale_item_id, batch_id),
        FOREIGN KEY (sale_item_id) REFERENCES sale_items (id) ON DELETE CASCADE,
        FOREIGN KEY (batch_id) REFERENCES stock_batches (id) ON DELETE RESTRICT
      )
    ''');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_stock_batches_product_expiry '
            'ON stock_batches (product_id, expires_at, id)');
  }

  Future<void> _migrateShiftReports(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shift_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        report_number INTEGER NOT NULL UNIQUE,
        shift_id INTEGER NOT NULL UNIQUE,
        report_type TEXT NOT NULL DEFAULT 'z',
        snapshot_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        staff_id INTEGER,
        staff_name TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_shift_reports_created '
        'ON shift_reports (created_at DESC)');
  }

  Future<void> _seedPermissionDefaults(Database db) async {
    for (final role in <String>['manager', 'cashier']) {
      final allowed = defaultRolePermissions[role] ?? const <String>{};
      final approval = defaultApprovalPermissions[role] ?? const <String>{};
      for (final permission in PermissionKey.values) {
        await db.insert(
          'role_permissions',
          {
            'role': role,
            'permission': permission.wire,
            'allowed': allowed.contains(permission.wire) ? 1 : 0,
            'mode': approval.contains(permission.wire)
                ? 'approval'
                : allowed.contains(permission.wire)
                    ? 'allow'
                    : 'deny',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  Future<void> _migrateHeldCustomer(Database db) async {
    await _addColumnIfMissing(db, 'held_carts', 'customer_id', 'INTEGER');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_held_carts_customer ON held_carts (customer_id)');
  }

  Future<void> _migrateReordering(Database db) async {
    final supplierColumns = await db.rawQuery('PRAGMA table_info(suppliers)');
    final names = supplierColumns.map((row) => row['name']).toSet();
    for (final column in <String>[
      'lead_time_days',
      'payment_terms',
      'order_channel',
    ]) {
      if (!names.contains(column)) {
        await db.execute('ALTER TABLE suppliers ADD COLUMN $column TEXT');
      }
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        product_id INTEGER NOT NULL,
        supplier_id INTEGER NOT NULL,
        supplier_sku TEXT,
        pack_id INTEGER,
        preferred INTEGER NOT NULL DEFAULT 0,
        synced_to_backend INTEGER NOT NULL DEFAULT 0,
        UNIQUE(product_id, supplier_id),
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE CASCADE
      )
    ''');
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
        staff_name TEXT NOT NULL
        ,synced_to_backend INTEGER NOT NULL DEFAULT 0
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
        FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_product_suppliers_product ON product_suppliers (product_id, preferred)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier ON purchase_orders (supplier_id, status, created_at DESC)');
  }

  Future<void> _migrateProductPacks(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_packs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        product_id INTEGER NOT NULL,
        variant_id INTEGER,
        name TEXT NOT NULL,
        barcode TEXT NOT NULL UNIQUE,
        units_per_pack REAL NOT NULL,
        unit_cost_minor INTEGER NOT NULL DEFAULT 0,
        sell_price_minor INTEGER,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_product_packs_product ON product_packs (product_id, active)');
    final columns = await db.rawQuery('PRAGMA table_info(sale_items)');
    final names = columns.map((row) => row['name']).toSet();
    if (!names.contains('pack_id')) {
      await db.execute('ALTER TABLE sale_items ADD COLUMN pack_id INTEGER');
    }
    if (!names.contains('pack_qty')) {
      await db.execute('ALTER TABLE sale_items ADD COLUMN pack_qty REAL');
    }
  }

  Future<void> _migratePackHeldLines(Database db) async {
    await _addColumnIfMissing(db, 'held_cart_lines', 'pack_id', 'INTEGER');
    await _addColumnIfMissing(db, 'held_cart_lines', 'pack_qty', 'REAL');
  }

  Future<void> _migrateIncomingPayments(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS incoming_payments (
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
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_incoming_payments_status ON incoming_payments (status, received_at DESC)');
    await _createIncomingPaymentClaimsTable(db);
  }

  Future<void> _createIncomingPaymentClaimsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS incoming_payment_claims (
        remote_id TEXT PRIMARY KEY,
        sale_id INTEGER NOT NULL,
        sale_uuid TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_incoming_payment_claims_status '
        'ON incoming_payment_claims (status, updated_at)');
  }

  Future<void> _migrateBackupLog(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS backup_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        kind TEXT NOT NULL,
        path TEXT,
        created_at TEXT NOT NULL,
        clear_bytes INTEGER NOT NULL DEFAULT 0,
        manifest_json TEXT,
        status TEXT NOT NULL DEFAULT 'written'
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_backup_log_created ON backup_log (created_at DESC)');
  }

  Future<void> _migrateStocktake(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_counts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        started_at TEXT NOT NULL,
        name TEXT,
        scope_type TEXT NOT NULL DEFAULT 'all',
        scope_ref TEXT,
        sales_mode TEXT NOT NULL DEFAULT 'keep_selling',
        completed_at TEXT,
        applied_at TEXT,
        applied_by INTEGER,
        note TEXT,
        status TEXT NOT NULL DEFAULT 'in_progress',
        blind INTEGER NOT NULL DEFAULT 0,
        freeze INTEGER NOT NULL DEFAULT 0,
        staff_id INTEGER,
        staff_name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_count_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        count_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        variant_id INTEGER,
        product_name TEXT NOT NULL,
        expected_qty REAL NOT NULL,
        counted_qty REAL,
        counted_by INTEGER,
        recount_required INTEGER NOT NULL DEFAULT 0,
        counted_at TEXT,
        note TEXT,
        FOREIGN KEY (count_id) REFERENCES stock_counts (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_count_lines_count ON stock_count_lines (count_id, product_id, variant_id)');
  }

  Future<void> _migrateCashDrawer(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS drawer_events (
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
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_drawer_events_created ON drawer_events (created_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_drawer_events_shift ON drawer_events (shift_id, created_at DESC)');
  }

  Future<void> _migrateReceiptShares(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS receipt_shares (
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
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_receipt_shares_sale ON receipt_shares (sale_id, created_at)');
  }

  Future<void> _migrateHeldCarts(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS held_carts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        staff_id INTEGER,
        staff_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'held'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS held_cart_lines (
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
        FOREIGN KEY (held_cart_id) REFERENCES held_carts (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_held_cart_lines_cart ON held_cart_lines (held_cart_id)');
  }

  Future<void> _migrateSplitPaymentPending(Database db) async {
    await _addColumnIfMissing(
        db, 'pending_payments', 'tender_amount_minor', 'INTEGER');
    await _addColumnIfMissing(
        db, 'pending_payments', 'intended_total_minor', 'INTEGER');
  }

  // ---------------- Discounts and price overrides (v32) ----------------

  Future<void> _migrateDiscounts(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS discount_reasons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    for (final name in const [
      'Staff discount',
      'Loyalty',
      'Damaged packaging',
      'Promotion',
      'Other',
    ]) {
      await db.insert('discount_reasons', {'name': name},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await _addColumnIfMissing(
        db, 'sale_items', 'list_unit_price_minor', 'INTEGER');
    await _addColumnIfMissing(
        db, 'sale_items', 'discount_minor', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'sale_items', 'discount_reason_id', 'INTEGER');
    await _addColumnIfMissing(
        db, 'sale_items', 'price_overridden', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, 'sales', 'subtotal_minor', 'INTEGER');
    await _addColumnIfMissing(
        db, 'sales', 'order_discount_minor', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'sales', 'order_discount_reason_id', 'INTEGER');
    await _addColumnIfMissing(db, 'sales', 'discount_approved_by', 'INTEGER');
  }

  // ---------------- Expenses and till movements (v31) ----------------

  Future<void> _migrateExpenses(Database db) => _createExpenseTables(db);

  Future<void> _createExpenseTables(Database db) async {
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

  Future<void> _createExpensePaymentsTable(Database db) async {
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
  }

  // ---------------- Customers, credit accounts and repayments (v30) ----------

  /// The tables a credit account is written to.
  ///
  /// Additive only. Existing sales gain an (optional) customer link, and every
  /// other table is new. The CREDIT LEDGER is append-only: a correction is a
  /// new row, never an edit, and `customers.balance_minor` is a cache of the
  /// ledger's sum maintained inside the transaction that writes the row.
  Future<void> _migrateCustomers(Database db) async {
    await _createCreditTables(db);
    await _addColumnIfMissing(db, 'sales', 'customer_id', 'INTEGER');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales (customer_id)');
  }

  /// The tables a credit account is written to — ONE definition, used by the
  /// migration and by a fresh install.
  Future<void> _createCreditTables(Database db) async {
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
    // Name uniqueness among ACTIVE customers is checked at write time rather
    // than by index: SQLite cannot express "unique where active = 1" without a
    // partial index, and a deactivated customer's name must be reusable.
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
        approved_by INTEGER,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_credit_ledger_customer '
        'ON credit_ledger (customer_id, created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_credit_ledger_shift '
        'ON credit_ledger (shift_id)');
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
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_credit_allocations_payment '
            'ON credit_allocations (payment_entry_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_credit_allocations_charge '
        'ON credit_allocations (charge_entry_id)');
  }

  // ---------------- A receive-session draft (v30) ----------------

  /// The draft a half-filled receive-stock session autosaves into.
  ///
  /// ONE row per staff member, upserted as the session changes. A delivery
  /// half-scanned at the counter loses nothing when the app is killed — the
  /// next open of the flow offers the draft back (spec 6.3.4). It holds a
  /// JSON payload rather than a mirrored table of lines because the draft's
  /// only reader is the same sheet that wrote it.
  Future<void> _migrateRestockDraft(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS receive_drafts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staff_id INTEGER UNIQUE,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  /// Saves (or replaces) the caller's receive-session draft. Null payload
  /// clears it — that is what a POSTED delivery calls after committing.
  Future<void> saveReceiveDraft(
      int? staffId, Map<String, Object?>? payload) async {
    final db = await database;
    if (payload == null) {
      await db.delete('receive_drafts',
          where: staffId == null ? 'staff_id IS NULL' : 'staff_id = ?',
          whereArgs: staffId == null ? null : [staffId]);
      return;
    }
    await db.insert(
      'receive_drafts',
      {
        'staff_id': staffId,
        'payload': jsonEncode(payload),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The caller's receive-session draft, or null.
  Future<Map<String, dynamic>?> getReceiveDraft(int? staffId) async {
    final rows = await (await database).query('receive_drafts',
        where: staffId == null ? 'staff_id IS NULL' : 'staff_id = ?',
        whereArgs: staffId == null ? null : [staffId],
        limit: 1);
    if (rows.isEmpty) return null;
    final raw = rows.first['payload'] as String?;
    if (raw == null || raw.isEmpty) return null;
    return (jsonDecode(raw) as Map<String, dynamic>);
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
        synced_to_backend INTEGER NOT NULL DEFAULT 0,
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
        supplier_pin TEXT,
        etims_invoice_ref TEXT,
        input_vat_minor INTEGER,
        tax_evidence_status TEXT NOT NULL DEFAULT 'needs_review',
        received_at TEXT NOT NULL,
        staff_id INTEGER,
        staff_name TEXT NOT NULL,
        total_cost_minor INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'posted',
        note TEXT,
        synced_to_backend INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _ensurePurchaseTaxEvidenceColumns(db);

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
        expiry_date TEXT,
        batch_code TEXT,
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

  Future<void> _ensurePurchaseTaxEvidenceColumns(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'stock_receipts'");
    if (tables.isEmpty) return;
    await _addColumnIfMissing(db, 'stock_receipts', 'supplier_pin', 'TEXT');
    await _addColumnIfMissing(
        db, 'stock_receipts', 'etims_invoice_ref', 'TEXT');
    await _addColumnIfMissing(
        db, 'stock_receipts', 'input_vat_minor', 'INTEGER');
    await _addColumnIfMissing(db, 'stock_receipts', 'tax_evidence_status',
        "TEXT NOT NULL DEFAULT 'needs_review'");
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
    await _createReturnRefundAllocationsTable(db);
  }

  Future<void> _createReturnRefundAllocationsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_return_refunds (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_id INTEGER NOT NULL,
        sale_payment_id INTEGER,
        method TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        reference TEXT,
        FOREIGN KEY (return_id) REFERENCES sale_returns (id) ON DELETE CASCADE,
        FOREIGN KEY (sale_payment_id) REFERENCES sale_payments (id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_return_refunds_return ON sale_return_refunds (return_id)');
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
    await _ensureTaxRuleSnapshotColumns(db);
    await _migrateLaybys(db);
    await _migrateExchanges(db);
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
    await _migrateSaleBuyerSnapshot(db);
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
        balance_after REAL NOT NULL,
        synced_to_backend INTEGER NOT NULL DEFAULT 0
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
      defaultValue: 'https://duka-pos-backend.brianbmk332.workers.dev/api',
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
    await _createShopProfileTable(db);
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

  Future<void> _createShopProfileTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS shop_profile (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      profile TEXT NOT NULL DEFAULT 'duka',
      updated_at TEXT NOT NULL
    )''');
  }

  Future<void> _createFinancialEventTable(Database db) async {
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
    await _addColumnIfMissing(db, 'financial_events', 'synced_to_backend',
        'INTEGER NOT NULL DEFAULT 0');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_financial_events_occurred '
        'ON financial_events (occurred_at_utc, id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_financial_events_source '
        'ON financial_events (source_type, source_id)');
  }

  Future<void> _createOwnerTransactionsTable(Database db) async {
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_owner_transactions_date '
        'ON owner_transactions (created_at, id)');
  }

  Future<void> _createOpenFinanceTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS cost_pools (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      pool_type TEXT NOT NULL CHECK (pool_type IN ('lot', 'rolling_stock')),
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
    await db.execute('''CREATE TABLE IF NOT EXISTS jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      customer_name TEXT,
      title TEXT NOT NULL,
      quote_minor INTEGER,
      final_price_minor INTEGER,
      due_at TEXT,
      status TEXT NOT NULL DEFAULT 'open',
      created_at TEXT NOT NULL,
      closed_at TEXT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS job_costs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      job_id INTEGER NOT NULL,
      cost_type TEXT NOT NULL,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      paid_from TEXT NOT NULL DEFAULT 'other',
      description TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (job_id) REFERENCES jobs (id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS job_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      job_id INTEGER NOT NULL,
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      payment_method TEXT NOT NULL,
      reference TEXT,
      shift_id INTEGER,
      created_at TEXT NOT NULL,
      FOREIGN KEY (job_id) REFERENCES jobs (id)
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cost_pool_entries_pool '
        'ON cost_pool_entries (pool_id, created_at)');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_sale_pool_allocations_sale '
            'ON sale_pool_allocations (sale_id, created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_job_costs_job ON job_costs (job_id, created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_job_payments_job '
        'ON job_payments (job_id, created_at)');
  }

  /// Appends one normalized financial fact and chains it to the previous fact.
  ///
  /// This method is only called from the same SQLite transaction as its source
  /// writer. A failed event insert therefore rolls back the sale/expense too;
  /// reports never observe a source row without its financial contract.
  Future<int> _appendFinancialEvent({
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
    final uuid = _newUuid();
    final metadataJson = jsonEncode(metadata);
    final canonical = _financialEventCanonical(
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

  Map<String, Object?> _financialEventCanonical({
    required String uuid,
    required String eventType,
    required String sourceType,
    required int? sourceId,
    required String occurredAtUtc,
    required int revenueMinor,
    required int cashInMinor,
    required int cashOutMinor,
    required int cogsMinor,
    required int operatingExpenseMinor,
    required int taxCollectedMinor,
    required int receivableDeltaMinor,
    required int payableDeltaMinor,
    required int customerDepositDeltaMinor,
    required int inventoryDeltaMilliunits,
    required String metadataJson,
    required String? previousHash,
  }) {
    return <String, Object?>{
      'uuid': uuid,
      'event_type': eventType,
      'source_type': sourceType,
      'source_id': sourceId,
      'occurred_at_utc': occurredAtUtc,
      'revenue_minor': revenueMinor,
      'cash_in_minor': cashInMinor,
      'cash_out_minor': cashOutMinor,
      'cogs_minor': cogsMinor,
      'operating_expense_minor': operatingExpenseMinor,
      'tax_collected_minor': taxCollectedMinor,
      'receivable_delta_minor': receivableDeltaMinor,
      'payable_delta_minor': payableDeltaMinor,
      'customer_deposit_delta_minor': customerDepositDeltaMinor,
      'inventory_delta_milliunits': inventoryDeltaMilliunits,
      'metadata_json': metadataJson,
      'previous_hash': previousHash,
    };
  }

  /// Verifies the append-only financial-event chain and every event payload.
  ///
  /// This is intentionally read-only and cheap enough for restore/startup
  /// checks. A false result means a restored or synced ledger must not be
  /// treated as financially trustworthy until it is investigated.
  Future<bool> verifyFinancialEventIntegrity() async {
    final rows = await (await database).query(
      'financial_events',
      orderBy: 'id ASC',
    );
    return _verifyFinancialEventRows(rows);
  }

  bool _verifyFinancialEventRows(Iterable<Map<String, Object?>> rows) {
    String? previousHash;
    for (final row in rows) {
      final rowPreviousHash = row['previous_hash'] as String?;
      if (rowPreviousHash != previousHash) return false;
      final canonical = _financialEventCanonical(
        uuid: row['uuid'] as String,
        eventType: row['event_type'] as String,
        sourceType: row['source_type'] as String,
        sourceId: (row['source_id'] as num?)?.toInt(),
        occurredAtUtc: row['occurred_at_utc'] as String,
        revenueMinor: (row['revenue_minor'] as num).toInt(),
        cashInMinor: (row['cash_in_minor'] as num).toInt(),
        cashOutMinor: (row['cash_out_minor'] as num).toInt(),
        cogsMinor: (row['cogs_minor'] as num).toInt(),
        operatingExpenseMinor: (row['operating_expense_minor'] as num).toInt(),
        taxCollectedMinor: (row['tax_collected_minor'] as num).toInt(),
        receivableDeltaMinor: (row['receivable_delta_minor'] as num).toInt(),
        payableDeltaMinor: (row['payable_delta_minor'] as num).toInt(),
        customerDepositDeltaMinor:
            (row['customer_deposit_delta_minor'] as num).toInt(),
        inventoryDeltaMilliunits:
            (row['inventory_delta_milliunits'] as num).toInt(),
        metadataJson: row['metadata_json'] as String,
        previousHash: rowPreviousHash,
      );
      final expectedHash =
          sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
      if (row['integrity_hash'] != expectedHash) return false;
      previousHash = expectedHash;
    }
    return true;
  }

  Future<List<FinancialEvent>> getFinancialEvents({
    int limit = 100,
    DateTime? sinceUtc,
    DateTime? untilUtc,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (sinceUtc != null) {
      where.add('occurred_at_utc >= ?');
      args.add(sinceUtc.toUtc().toIso8601String());
    }
    if (untilUtc != null) {
      where.add('occurred_at_utc < ?');
      args.add(untilUtc.toUtc().toIso8601String());
    }
    final rows = await (await database).query(
      'financial_events',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(FinancialEvent.fromMap).toList();
  }

  Future<List<FinancialEvent>> getUnsyncedFinancialEvents({
    int limit = 500,
  }) async {
    final rows = await (await database).query(
      'financial_events',
      where: 'synced_to_backend = 0',
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(FinancialEvent.fromMap).toList();
  }

  Future<void> markFinancialEventsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    await (await database).rawUpdate(
      'UPDATE financial_events SET synced_to_backend = 1 '
      'WHERE id IN (${List.filled(ids.length, '?').join(',')})',
      ids,
    );
  }

  /// Returns one reconciled total from the append-only event stream.
  ///
  /// [fromUtc] is inclusive and [untilUtc] is exclusive. The database stores
  /// UTC timestamps, so range boundaries are normalized before querying.
  Future<FinancialEventTotals> getFinancialEventTotals({
    DateTime? fromUtc,
    DateTime? untilUtc,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (fromUtc != null) {
      where.add('occurred_at_utc >= ?');
      args.add(fromUtc.toUtc().toIso8601String());
    }
    if (untilUtc != null) {
      where.add('occurred_at_utc < ?');
      args.add(untilUtc.toUtc().toIso8601String());
    }
    final rows = await (await database).query(
      'financial_events',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id ASC',
    );
    var totals = const FinancialEventTotals();
    for (final row in rows) {
      totals += FinancialEvent.fromMap(row);
    }
    return totals;
  }

  Future<FinancialStatement> getFinancialStatement({
    DateTime? fromUtc,
    DateTime? untilUtc,
    int openingCashMinor = 0,
    bool openingCashIsKnown = false,
  }) async {
    return FinancialStatement(
      totals: await getFinancialEventTotals(
        fromUtc: fromUtc,
        untilUtc: untilUtc,
      ),
      openingCashMinor: openingCashMinor,
      openingCashIsKnown: openingCashIsKnown,
    );
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
      reserved_qty REAL NOT NULL DEFAULT 0,
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
        reserved_qty REAL NOT NULL DEFAULT 0,
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
        reserved_qty REAL NOT NULL DEFAULT 0,
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
    // The customers and the credit ledger behind them. The same helper the
    // v30 upgrade uses, for the same reason.
    await _migrateCustomers(db);
    // The receive-session draft table, likewise.
    await _migrateRestockDraft(db);
    await _migrateExpenses(db);
    await _createExpensePaymentsTable(db);
    await _createProductPriceHistoryTable(db);
    await _migrateDiscounts(db);
    await _migrateSplitPaymentPending(db);
    await _migrateHeldCarts(db);
    await _migrateReceiptShares(db);
    await _migrateCashDrawer(db);
    await _migrateStocktake(db);
    await _migrateBackupLog(db);
    await _migrateProductPacks(db);
    await _createLabelPrintJobsTable(db);
    await _migrateReordering(db);
    await _migratePackHeldLines(db);
    await _migrateIncomingPayments(db);
    await _migrateHeldCustomer(db);
    await _migratePermissions(db);
    await _migrateExpiryBatches(db);
    await _migrateExpiryBatchMetadata(db);
    await _migrateShiftReports(db);
    await _migrateRemoteOperationalRecords(db);
    await _migrateSyncConflicts(db);
    await _migrateNotifications(db);
    await _createFinancialEventTable(db);
    await _createOwnerTransactionsTable(db);
    await _createOpenFinanceTables(db);
    await _ensureTaxRuleSnapshotColumns(db);
    await _migrateLaybys(db);
    await _migrateExchanges(db);

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

  Future<void> _ensureTaxRuleSnapshotColumns(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'sale_items'");
    if (tables.isEmpty) return;
    await _addColumnIfMissing(db, 'sale_items', 'tax_rule_id', 'TEXT');
    await _addColumnIfMissing(db, 'sale_items', 'tax_rule_version', 'INTEGER');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_tax_rule ON sale_items (tax_rule_id)');
  }

  // ---------------- Owner ----------------
  Future<bool> hasPermission({
    required String role,
    required String permission,
    int? staffId,
  }) async {
    if (role == ShopRole.admin.wire) return true;
    return (await permissionMode(
          role: role,
          permission: permission,
          staffId: staffId,
        )) !=
        PermissionMode.deny;
  }

  Future<PermissionMode> permissionMode({
    required String role,
    required String permission,
    int? staffId,
  }) async {
    if (role == ShopRole.admin.wire) return PermissionMode.allow;
    final db = await database;
    if (staffId != null) {
      final override = await db.query(
        'staff_permission_overrides',
        columns: ['allowed', 'mode'],
        where: 'staff_id = ? AND permission = ?',
        whereArgs: [staffId, permission],
        limit: 1,
      );
      if (override.isNotEmpty) return _permissionModeFromRow(override.first);
    }
    final rows = await db.query(
      'role_permissions',
      columns: ['allowed', 'mode'],
      where: 'role = ? AND permission = ?',
      whereArgs: [role, permission],
      limit: 1,
    );
    return rows.isEmpty
        ? PermissionMode.deny
        : _permissionModeFromRow(rows.first);
  }

  PermissionMode _permissionModeFromRow(Map<String, dynamic> row) {
    final raw = (row['mode'] as String?)?.trim().toLowerCase();
    return switch (raw) {
      'allow' => PermissionMode.allow,
      'approval' => PermissionMode.approval,
      _ => (row['allowed'] as num?)?.toInt() == 1
          ? PermissionMode.allow
          : PermissionMode.deny,
    };
  }

  Future<List<Map<String, dynamic>>> getPermissionMatrix() async =>
      (await database).query('role_permissions', orderBy: 'role, permission');

  Future<void> setRolePermission({
    required String role,
    required String permission,
    required bool allowed,
  }) async {
    await (await database).insert(
      'role_permissions',
      {
        'role': role,
        'permission': permission,
        'allowed': allowed ? 1 : 0,
        'mode': allowed ? 'allow' : 'deny',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setRolePermissionMode({
    required String role,
    required String permission,
    required PermissionMode mode,
  }) async {
    await (await database).insert(
      'role_permissions',
      {
        'role': role,
        'permission': permission,
        'allowed': mode == PermissionMode.deny ? 0 : 1,
        'mode': mode.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setStaffPermissionOverride({
    required int staffId,
    required String permission,
    required bool allowed,
  }) async {
    await (await database).insert(
      'staff_permission_overrides',
      {
        'staff_id': staffId,
        'permission': permission,
        'allowed': allowed ? 1 : 0,
        'mode': allowed ? 'allow' : 'deny',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setStaffPermissionOverrideMode({
    required int staffId,
    required String permission,
    required PermissionMode mode,
  }) async {
    await (await database).insert(
      'staff_permission_overrides',
      {
        'staff_id': staffId,
        'permission': permission,
        'allowed': mode == PermissionMode.deny ? 0 : 1,
        'mode': mode.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearStaffPermissionOverride({
    required int staffId,
    required String permission,
  }) async {
    await (await database).delete('staff_permission_overrides',
        where: 'staff_id = ? AND permission = ?',
        whereArgs: [staffId, permission]);
  }

  Future<List<Map<String, dynamic>>> getStaffPermissionOverrides(
          int staffId) async =>
      (await database).query('staff_permission_overrides',
          where: 'staff_id = ?', whereArgs: [staffId]);

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

  /// The stored PIN hash of one staff member, for an approval sheet's check.
  ///
  /// It stays IN the helper of the verification only — the hash is never
  /// listed, logged, or returned for display, and the caller keeps it in its
  /// own local for exactly the verify.
  Future<String?> staffPinHash(int staffId) async {
    final rows = await (await database).query('staff',
        columns: <String>['pin_hash'],
        where: 'id = ? AND active = 1',
        whereArgs: [staffId],
        limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['pin_hash'] as String?;
  }

  Future<int> addStaff(Staff staff) async {
    final values = staff.toMap()..remove('id');
    return (await database).insert('staff', values);
  }

  Future<void> setStaffRemoteId(int id, String remoteId) async {
    await (await database).update('staff', {'remote_id': remoteId},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Refreshes a locally provisioned staff profile without touching its PIN.
  /// PIN hashes never cross the network, so a new device must still provision
  /// its local PIN before that person can sign in there.
  Future<void> mergeRemoteStaff({
    required String remoteId,
    required String name,
    String? username,
    required String role,
    required bool active,
  }) async {
    if (remoteId.trim().isEmpty) {
      throw ArgumentError.value(remoteId, 'remoteId');
    }
    final db = await database;
    await db.update(
      'staff',
      {
        'name': name,
        if (username != null && username.trim().isNotEmpty)
          'username': username.trim(),
        'role': role,
        'active': active ? 1 : 0,
      },
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
  }

  /// Materialises a staff member authenticated by the backend so the same
  /// person can use this till when it is offline. Only the locally derived
  /// PIN hash is stored; the backend never sends PIN material.
  Future<Staff> mergeAuthenticatedStaff({
    required String remoteId,
    required String username,
    required String name,
    required String role,
    required String pinHash,
  }) async {
    final db = await database;
    final existing = await db.query(
      'staff',
      where: 'remote_id = ? OR username = ?',
      whereArgs: [remoteId, username],
      limit: 1,
    );
    int id;
    if (existing.isEmpty) {
      id = await db.insert('staff', {
        'name': name,
        'username': username,
        'pin_hash': pinHash,
        'active': 1,
        'remote_id': remoteId,
        'role': role,
      });
    } else {
      id = (existing.first['id'] as num).toInt();
      await db.update(
        'staff',
        {
          'name': name,
          'username': username,
          'pin_hash': pinHash,
          'active': 1,
          'remote_id': remoteId,
          'role': role,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    final row =
        await db.query('staff', where: 'id = ?', whereArgs: [id], limit: 1);
    return Staff.fromMap(row.single);
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

  Future<Product?> getProductById(int id) async {
    final rows = await (await database).query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  /// The stock baseline written when a product first entered this till. A
  /// product can be sold before its first online sync, so the server must get
  /// this opening balance and then replay the later movement deltas.
  Future<double?> openingStockQtyForProduct(int productId) async {
    final rows = await (await database).query(
      'stock_movements',
      columns: ['balance_after'],
      where: 'product_id = ? AND variant_id IS NULL AND movement_type = ?',
      whereArgs: [productId, StockMovementType.opening.wire],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['balance_after'] as num?)?.toDouble();
  }

  /// The local stock changes the server has not acknowledged yet.
  ///
  /// A pulled product count is a remote baseline. Adding only these
  /// non-opening movements keeps an offline sale or receipt visible locally
  /// without double-counting the opening balance that product sync already
  /// established on the server.
  Future<double> unsyncedStockDeltaForProduct(int productId) async {
    final rows = await (await database).rawQuery('''
      SELECT COALESCE(SUM(qty_delta), 0) AS delta
        FROM stock_movements
       WHERE product_id = ?
         AND variant_id IS NULL
         AND synced_to_backend = 0
         AND movement_type != ?
    ''', [productId, StockMovementType.opening.wire]);
    return (rows.first['delta'] as num?)?.toDouble() ?? 0;
  }

  /// Applies the shared catalogue fields received from another device. A
  /// remote id is the merge key; the local row id is never trusted across
  /// phones. Local-only selling fields (variants, unit, photos) remain intact.
  Future<void> mergeRemoteProduct({
    required String remoteId,
    required String name,
    required String category,
    required int costPriceMinor,
    required int sellPriceMinor,
    required double stockQty,
    required int reorderLevel,
    required int bottleMl,
    String unit = 'each',
    double millilitresPerKilogram = 0,
    required int? halfPriceMinor,
    required int? quarterPriceMinor,
    required String exciseStampBatch,
    required bool active,
    double unsyncedStockDelta = 0,
  }) async {
    if (remoteId.trim().isEmpty) {
      throw ArgumentError.value(remoteId, 'remoteId');
    }
    final db = await database;
    await db.transaction((txn) async {
      final values = <String, Object?>{
        'name': name,
        'category': category,
        'cost_price': costPriceMinor,
        'sell_price': sellPriceMinor,
        'stock_qty': stockQty + unsyncedStockDelta,
        'reorder_level': reorderLevel,
        'bottle_ml': bottleMl,
        'unit': unit,
        'ml_per_kg': millilitresPerKilogram,
        'half_price': halfPriceMinor,
        'quarter_price': quarterPriceMinor,
        'excise_stamp_batch': exciseStampBatch,
        'active': active ? 1 : 0,
        'remote_id': remoteId,
        'updated_at': DateTime.now().toIso8601String(),
      };
      final existing = await txn.query('products',
          columns: ['id'],
          where: 'remote_id = ?',
          whereArgs: [remoteId],
          limit: 1);
      final int productId;
      final double previousLedger;
      if (existing.isEmpty) {
        productId = await txn.insert('products', values);
        previousLedger = 0;
      } else {
        productId = (existing.first['id'] as num).toInt();
        final ledgerRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(qty_delta), 0) AS total '
          'FROM stock_movements WHERE product_id = ? AND variant_id IS NULL',
          [productId],
        );
        previousLedger = (ledgerRows.first['total'] as num?)?.toDouble() ?? 0;
        await txn.update('products', values,
            where: 'id = ?', whereArgs: [productId]);
      }

      // The remote count is a baseline, not a new unsynced sale or receipt.
      // Bring the local ledger to the same target once; a later identical pull
      // computes a zero delta and adds nothing.
      final target = stockQty + unsyncedStockDelta;
      final delta = target - previousLedger;
      if (delta.abs() > _qtyEpsilon) {
        await txn.insert('stock_movements', <String, Object?>{
          'uuid': _newUuid(),
          'created_at': DateTime.now().toIso8601String(),
          'product_id': productId,
          'variant_id': null,
          'movement_type': StockMovementType.remoteSync.wire,
          'qty_delta': delta,
          'unit_cost_minor': null,
          'reference_type': 'remote_product_sync',
          'reference_id': null,
          'batch_id': null,
          'staff_id': null,
          'staff_name': null,
          'note': 'Remote stock baseline',
          'balance_after': target,
          'synced_to_backend': 1,
        });
      }
    });
  }

  /// Base units sold per product in the recent window, used only as a reorder
  /// signal. It is deliberately a single grouped query so opening the reorder
  /// screen does not perform one scan per product.
  Future<Map<int, double>> getSalesVelocity({int days = 30}) async {
    if (days <= 0) throw ArgumentError.value(days, 'days');
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final rows = await (await database).rawQuery('''
      SELECT i.product_id, COALESCE(SUM(i.qty), 0) AS units
      FROM sale_items i JOIN sales s ON s.id = i.sale_id
      WHERE s.created_at >= ?
      GROUP BY i.product_id
    ''', [cutoff]);
    return <int, double>{
      for (final row in rows)
        (row['product_id'] as num).toInt():
            ((row['units'] as num?)?.toDouble() ?? 0) / days,
    };
  }

  /// Active catalogue items with the lowest movement in a bounded period.
  ///
  /// The left join intentionally keeps products with zero sales: a product
  /// that never moved is the clearest slow-mover signal. The calculation stays
  /// in SQLite so a large catalogue does not become a Dart-side scan.
  Future<List<SlowMoverRow>> getSlowMovingProducts({
    required DateTime since,
    DateTime? until,
    int limit = 5,
  }) async {
    final end = until ?? DateTime.now();
    final days = math.max(1, end.difference(since).inMinutes / (60 * 24));
    final rows = await (await database).rawQuery('''
      SELECT p.*,
             COALESCE(SUM(
               CASE WHEN s.created_at >= ? AND s.created_at < ?
                    THEN i.qty ELSE 0 END
             ), 0) AS moved_units
      FROM products p
      LEFT JOIN sale_items i ON i.product_id = p.id
      LEFT JOIN sales s ON s.id = i.sale_id
      WHERE p.active = 1
      GROUP BY p.id
      ORDER BY moved_units ASC, p.name ASC
      LIMIT ?
    ''', [since.toIso8601String(), end.toIso8601String(), limit.clamp(1, 50)]);
    return rows.map((row) {
      final product = Product.fromMap(row);
      final moved = (row['moved_units'] as num?)?.toDouble() ?? 0;
      return SlowMoverRow(product: product, unitsPerDay: moved / days);
    }).toList();
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

  /// Resolves either a product barcode or a pack barcode in one lookup path.
  /// Pack codes are checked against product codes before insertion, so this is
  /// deterministic even though the two ledgers are separate tables.
  Future<({Product? product, ProductPack? pack})> getSellableByBarcode(
      String barcode) async {
    final product = await getProductByBarcode(barcode);
    if (product != null) return (product: product, pack: null);
    final rows = await (await database).query(
      'product_packs',
      where: 'barcode = ? AND active = 1',
      whereArgs: [barcode],
      limit: 1,
    );
    return (
      product: null,
      pack: rows.isEmpty ? null : ProductPack.fromMap(rows.first),
    );
  }

  Future<List<ProductPack>> getProductPacks(int productId) async {
    final rows = await (await database).query(
      'product_packs',
      where: 'product_id = ? AND active = 1',
      whereArgs: [productId],
      orderBy: 'name',
    );
    return rows.map(ProductPack.fromMap).toList();
  }

  Future<int> addProductPack({
    required String uuid,
    required int productId,
    required String name,
    required String barcode,
    required double unitsPerPack,
    required Money unitCost,
    Money? sellPrice,
    int? variantId,
  }) async {
    if (uuid.trim().isEmpty || name.trim().isEmpty || barcode.trim().isEmpty) {
      throw ArgumentError('Pack identity is required');
    }
    if (!unitsPerPack.isFinite || unitsPerPack <= 0) {
      throw ArgumentError.value(unitsPerPack, 'unitsPerPack');
    }
    final db = await database;
    if (variantId != null) {
      final variant = await db.query(
        'product_variants',
        columns: ['id'],
        where: 'id = ? AND product_id = ? AND active = 1',
        whereArgs: [variantId, productId],
        limit: 1,
      );
      if (variant.isEmpty) throw StateError('Pack variant not found');
    }
    final productBarcode = await db.query(
      'product_barcodes',
      columns: ['barcode'],
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (productBarcode.isNotEmpty) {
      throw StateError('That barcode already belongs to a product');
    }
    return db.insert('product_packs', {
      'uuid': uuid,
      'product_id': productId,
      'variant_id': variantId,
      'name': name.trim(),
      'barcode': barcode,
      'units_per_pack': unitsPerPack,
      'unit_cost_minor': unitCost.minorUnits,
      'sell_price_minor': sellPrice?.minorUnits,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deactivateProductPack(int id) async {
    await (await database).update('product_packs', {'active': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> createLabelPrintJob({
    required String uuid,
    required int productId,
    required String productName,
    required String barcode,
    required int priceMinor,
    required int quantity,
    required int paperWidth,
  }) async {
    if (quantity < 1) throw ArgumentError.value(quantity, 'quantity');
    final now = DateTime.now().toIso8601String();
    return (await database).insert('label_print_jobs', {
      'uuid': uuid,
      'product_id': productId,
      'product_name': productName,
      'barcode': barcode,
      'price_minor': priceMinor,
      'quantity': quantity,
      'paper_width': paperWidth,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<Map<String, dynamic>?> getLabelPrintJob(int id) async {
    final rows = await (await database).query(
      'label_print_jobs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateLabelPrintJob({
    required int id,
    int? printedQuantity,
    String? status,
    String? error,
  }) async {
    final values = <String, Object?>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (printedQuantity != null) values['printed_quantity'] = printedQuantity;
    if (status != null) values['status'] = status;
    if (error != null) values['error'] = error;
    await (await database)
        .update('label_print_jobs', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getPendingLabelPrintJobs() async =>
      (await database).query(
        'label_print_jobs',
        where: "status != 'completed'",
        orderBy: 'updated_at DESC',
      );

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
  Future<({Product product, ProductVariant? variant, ProductPack? pack})?>
      getScanTarget(String barcode) async {
    final rows = await (await database).rawQuery(
      '''SELECT p.*, b.variant_id AS _matched_variant
         FROM products p
         JOIN product_barcodes b ON b.product_id = p.id
        WHERE b.barcode = ? AND p.active = 1
        LIMIT 1''',
      [barcode],
    );
    if (rows.isEmpty) {
      final packRows = await (await database).rawQuery(
        '''SELECT p.*, k.id AS _pack_id, k.uuid AS _pack_uuid,
                  k.name AS _pack_name, k.barcode AS _pack_barcode,
                  k.variant_id AS _pack_variant,
                  k.units_per_pack AS _pack_units,
                  k.unit_cost_minor AS _pack_cost,
                  k.sell_price_minor AS _pack_sell, k.active AS _pack_active
           FROM product_packs k JOIN products p ON p.id = k.product_id
           WHERE k.barcode = ? AND k.active = 1 AND p.active = 1 LIMIT 1''',
        [barcode],
      );
      if (packRows.isEmpty) return null;
      final row = packRows.first;
      final pack = ProductPack(
        id: row['_pack_id'] as int,
        uuid: row['_pack_uuid'] as String,
        productId: row['id'] as int,
        variantId: (row['_pack_variant'] as num?)?.toInt(),
        name: row['_pack_name'] as String,
        barcode: row['_pack_barcode'] as String,
        unitsPerPack: (row['_pack_units'] as num).toDouble(),
        unitCost: Money.fromMinor((row['_pack_cost'] as num).toInt()),
        sellPrice: (row['_pack_sell'] as num?) == null
            ? null
            : Money.fromMinor((row['_pack_sell'] as num).toInt()),
        active: (row['_pack_active'] as num? ?? 1) == 1,
      );
      final variantId = pack.variantId;
      final variant =
          variantId == null ? null : await getVariantById(variantId);
      return (product: Product.fromMap(row), variant: variant, pack: pack);
    }
    final variantId = rows.first['_matched_variant'] as int?;
    if (variantId == null) {
      return (product: Product.fromMap(rows.first), variant: null, pack: null);
    }
    final variant = await getVariantById(variantId);
    return (product: Product.fromMap(rows.first), variant: variant, pack: null);
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

  /// The shop's selected profile. Legacy shops deliberately resolve to Duka
  /// until the owner explicitly chooses another profile.
  Future<ShopProfile> getShopProfile() async {
    final rows = await (await database).query('shop_profile', limit: 1);
    return ShopProfile.fromWire(
        rows.isEmpty ? null : rows.first['profile'] as String?);
  }

  Future<void> setShopProfile(ShopProfile profile) async {
    await (await database).insert(
      'shop_profile',
      {
        'id': 1,
        'profile': profile.wireValue,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<NotificationPreference>> getNotificationPreferences(
      int staffId) async {
    final rows = await (await database).query(
      'notification_prefs',
      where: 'staff_id = ?',
      whereArgs: [staffId],
    );
    return rows
        .map((row) => NotificationPreference(
              staffId: staffId,
              type: ShopNotificationTypeWire.parse(row['type'] as String?) ??
                  ShopNotificationType.lowStock,
              enabled: row['enabled'] == 1,
              quietStartMinutes: row['quiet_start'] as int?,
              quietEndMinutes: row['quiet_end'] as int?,
            ))
        .toList(growable: false);
  }

  Future<void> saveNotificationPreference(
      NotificationPreference preference) async {
    await (await database).insert(
      'notification_prefs',
      {
        'staff_id': preference.staffId,
        'type': preference.type.wire,
        'enabled': preference.enabled ? 1 : 0,
        'quiet_start': preference.quietStartMinutes,
        'quiet_end': preference.quietEndMinutes,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<NotificationRecord?> latestNotification({
    required int staffId,
    required ShopNotificationType type,
    required String dedupeKey,
  }) async {
    final rows = await (await database).query(
      'notification_log',
      where: 'staff_id = ? AND type = ? AND dedupe_key = ?',
      whereArgs: [staffId, type.wire, dedupeKey],
      orderBy: 'fired_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _notificationFromRow(rows.first);
  }

  Future<int> recordNotification({
    required int staffId,
    required ShopNotificationType type,
    required String dedupeKey,
    required int count,
    required DateTime firedAt,
  }) async {
    return (await database).insert('notification_log', {
      'staff_id': staffId,
      'type': type.wire,
      'dedupe_key': dedupeKey,
      'count': count,
      'fired_at': firedAt.toUtc().toIso8601String(),
    });
  }

  /// Atomically applies the minimum interval and records the notification.
  ///
  /// Background callbacks and a foreground refresh can arrive together. A
  /// separate SELECT followed by INSERT would let both observe the same old
  /// row and emit the same alert.
  Future<bool> recordNotificationIfDue({
    required int staffId,
    required ShopNotificationType type,
    required String dedupeKey,
    required int count,
    required DateTime firedAt,
    required Duration minimumInterval,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'notification_log',
        where: 'staff_id = ? AND type = ? AND dedupe_key = ?',
        whereArgs: [staffId, type.wire, dedupeKey],
        orderBy: 'fired_at DESC, id DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final previous = _notificationFromRow(rows.first);
        if (firedAt.difference(previous.firedAt) < minimumInterval) {
          return false;
        }
      }
      await txn.insert('notification_log', {
        'staff_id': staffId,
        'type': type.wire,
        'dedupe_key': dedupeKey,
        'count': count,
        'fired_at': firedAt.toUtc().toIso8601String(),
      });
      return true;
    });
  }

  Future<void> markNotificationOpened(int id, {DateTime? openedAt}) async {
    await (await database).update(
      'notification_log',
      {'opened_at': (openedAt ?? DateTime.now()).toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<NotificationRecord>> recentNotifications({
    required int staffId,
    int limit = 20,
  }) async {
    final rows = await (await database).query(
      'notification_log',
      where: 'staff_id = ?',
      whereArgs: [staffId],
      orderBy: 'fired_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(_notificationFromRow).toList(growable: false);
  }

  Future<int> pruneNotifications(
      {Duration retain = const Duration(days: 90)}) async {
    final cutoff = DateTime.now().toUtc().subtract(retain).toIso8601String();
    return (await database).delete(
      'notification_log',
      where: 'fired_at < ?',
      whereArgs: [cutoff],
    );
  }

  NotificationRecord _notificationFromRow(Map<String, Object?> row) {
    return NotificationRecord(
      id: row['id']! as int,
      staffId: row['staff_id']! as int,
      type: ShopNotificationTypeWire.parse(row['type'] as String?) ??
          ShopNotificationType.lowStock,
      dedupeKey: row['dedupe_key']! as String,
      count: row['count']! as int,
      firedAt: DateTime.parse(row['fired_at']! as String).toLocal(),
      openedAt: row['opened_at'] == null
          ? null
          : DateTime.parse(row['opened_at']! as String).toLocal(),
    );
  }

  /// A portable, schema-aware snapshot of every local user-data table.  The
  /// inventory workbook is deliberately not used here: it cannot carry sales,
  /// staff, permissions, credit, shifts, audit history, queues or analytics
  /// source data, so restoring it would produce a deceptively incomplete shop.
  Future<Map<String, Object?>> exportFullSnapshot() async {
    final db = await database;
    // Keep the catalogue, ledgers, queues and audit history on one SQLite
    // snapshot. Reading each table in separate operations lets a sale or a
    // sync write land between related tables and creates a backup that never
    // existed as a valid workspace state.
    final tables = await db.transaction((txn) async {
      final tableRows = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      final result = <String, List<Map<String, Object?>>>{};
      for (final tableRow in tableRows) {
        final name = tableRow['name'] as String;
        final rows = await txn.query(name, orderBy: 'rowid');
        result[name] = [
          for (final row in rows) Map<String, Object?>.from(row),
        ];
      }
      return result;
    });
    final domainTables = <String, List<String>>{
      'financial': _snapshotDomainTables(tables, const <String>[
        'sales',
        'sale_items',
        'sale_payments',
        'sale_returns',
        'sale_return_items',
        'sale_return_refunds',
        'expenses',
        'expense_payments',
        'till_movements',
        'financial_events',
        'owner_transactions',
        'incoming_payments',
        'incoming_payment_claims',
        'credit_ledger',
        'credit_allocations',
        'laybys',
        'layby_items',
        'layby_payments',
        'exchanges',
        'stock_receipts',
        'stock_receipt_items',
        'purchase_orders',
        'purchase_order_lines',
        'shifts',
        'till_counts',
        'reconciliations',
        'cost_pools',
        'cost_pool_entries',
        'sale_pool_allocations',
      ]),
      'profile': _snapshotDomainTables(tables, const <String>[
        'shop_profile',
        'owner',
        'staff',
        'staff_deletion_tombstones',
        'role_permissions',
        'staff_permission_overrides',
        'shop_settings',
        'categories',
        'products',
        'product_barcodes',
        'product_variants',
        'product_packs',
        'suppliers',
        'product_suppliers',
      ]),
      // Tax/eTIMS is intentionally disabled in the current product behaviour.
      // Its persisted source data still travels with a full backup so it can
      // be enabled later without losing historical evidence.
      'tax': _snapshotDomainTables(tables, const <String>[
        'pending_etims',
        'sales',
        'sale_items',
        'stock_receipts',
        'stock_receipt_items',
        'financial_events',
        'shop_settings',
      ]),
    };
    return <String, Object?>{
      'format': 'duka-full-snapshot-v1',
      'schemaVersion': _schemaVersion,
      'workspaceKey': _workspaceKey,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
      'manifest': <String, int>{
        for (final entry in tables.entries) entry.key: entry.value.length,
      },
      'domainTables': domainTables,
      'media': await _exportSnapshotMedia(tables),
    };
  }

  static List<String> _snapshotDomainTables(
    Map<String, List<Map<String, Object?>>> tables,
    List<String> candidates,
  ) =>
      [
        for (final table in candidates)
          if (tables.containsKey(table)) table,
      ];

  /// Local images are deliberately not database blobs, but referenced images
  /// are still part of a complete portable restore.  Keep this list narrow:
  /// only product paths present in the snapshot and the device avatar are
  /// included, never an arbitrary file from the documents directory.
  Future<List<Map<String, String>>> _exportSnapshotMedia(
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    final paths = <String>{ProductImageStore.avatarRelativePath};
    for (final row in tables['products'] ?? const <Map<String, Object?>>[]) {
      final imagePath = row['image_path'];
      if (imagePath is String && imagePath.isNotEmpty) paths.add(imagePath);
    }
    final media = <Map<String, String>>[];
    final docs = await _applicationDocumentsDirectory();
    if (docs == null) return media;
    for (final relative in paths) {
      if (!_isSafeSnapshotPath(relative)) continue;
      final file = File(join(docs.path, relative));
      if (!await file.exists()) continue;
      media.add(<String, String>{
        'path': relative,
        'bytes': base64Encode(await file.readAsBytes()),
      });
    }
    return media;
  }

  static bool _isSafeSnapshotPath(String relative) {
    if (relative.isEmpty || isAbsolute(relative)) return false;
    final parts = relative.split(RegExp(r'[/\\]'));
    return parts.isNotEmpty &&
        !parts.any((part) => part.isEmpty || part == '.' || part == '..');
  }

  /// Restores a snapshot into the current workspace atomically.  The schema is
  /// owned by the running build; unknown snapshot tables are ignored so a
  /// newer backup can be inspected by an older build without arbitrary SQL.
  ///
  /// A device-bound backup stays locked to its workspace. A portable,
  /// passphrase-protected backup may be restored into the currently selected
  /// workspace on a replacement phone; the caller must opt into that boundary
  /// explicitly after the user has authenticated and chosen the destination.
  Future<void> restoreFullSnapshot(
    Map<String, Object?> snapshot, {
    bool allowWorkspaceMismatch = false,
  }) async {
    if (snapshot['format'] != 'duka-full-snapshot-v1' ||
        snapshot['tables'] is! Map ||
        snapshot['manifest'] is! Map) {
      throw const FormatException('Unsupported full backup');
    }
    final snapshotWorkspace = snapshot['workspaceKey'];
    if (snapshotWorkspace is! String ||
        snapshotWorkspace.isEmpty ||
        (!allowWorkspaceMismatch && snapshotWorkspace != _workspaceKey)) {
      throw const FormatException('Backup belongs to a different shop');
    }
    final db = await database;
    final availableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%'",
    );
    final available = {
      for (final row in availableRows) row['name'] as String,
    };
    final source = Map<Object?, Object?>.from(snapshot['tables']! as Map);
    final manifest = Map<Object?, Object?>.from(snapshot['manifest']! as Map);
    final domainTables = snapshot['domainTables'];
    if (domainTables != null) {
      if (domainTables is! Map) {
        throw const FormatException('Invalid backup domain manifest');
      }
      for (final domainEntry in domainTables.entries) {
        if (domainEntry.key is! String || domainEntry.value is! List) {
          throw const FormatException('Invalid backup domain manifest');
        }
        for (final table in domainEntry.value as List) {
          if (table is! String || !source.containsKey(table)) {
            throw const FormatException('Backup domain is incomplete');
          }
        }
      }
    }
    final tables = <String, List<Map<String, Object?>>>{};
    for (final entry in source.entries) {
      if (entry.key is! String || !available.contains(entry.key)) continue;
      if (entry.value is! List) {
        throw const FormatException('Invalid table rows');
      }
      final rawRows = entry.value as List;
      if (rawRows.any((row) => row is! Map)) {
        throw const FormatException('Invalid row in full backup');
      }
      final rows = [
        for (final row in rawRows) Map<String, Object?>.from(row as Map),
      ];
      final expected = manifest[entry.key];
      if (expected is! num || expected.toInt() != rows.length) {
        throw const FormatException('Full backup manifest does not match');
      }
      tables[entry.key as String] = rows;
    }
    final financialRows = tables['financial_events'];
    if (financialRows != null && !_verifyFinancialEventRows(financialRows)) {
      throw const FormatException('Financial event integrity check failed');
    }
    // Validate media before replacing any table. A malformed media entry must
    // fail like a malformed row, without leaving the database half-restored.
    _validateSnapshotMedia(snapshot['media']);
    // Filesystem writes cannot participate in SQLite's transaction. Stage the
    // new files first, then swap them with a byte-for-byte rollback plan. The
    // database is replaced only after that swap succeeds; if its transaction
    // fails, the old media is restored before the error reaches the caller.
    final mediaRollback = await _applySnapshotMedia(snapshot['media']);
    try {
      await db.execute('PRAGMA foreign_keys = OFF');
      try {
        await db.transaction((txn) async {
          // Replace only tables represented by the snapshot. This preserves
          // tables introduced by a newer schema when an older backup is
          // restored, and prevents a malformed/partial export from wiping
          // otherwise valid current data.
          for (final table in tables.keys) {
            await txn.delete(table);
          }
          for (final entry in tables.entries) {
            for (final row in entry.value) {
              await txn.insert(entry.key, row,
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
          final restoredFinancialRows = await txn.query(
            'financial_events',
            orderBy: 'id ASC',
          );
          if (!_verifyFinancialEventRows(restoredFinancialRows)) {
            throw const FormatException(
                'Restored financial event integrity check failed');
          }
        });
      } finally {
        await db.execute('PRAGMA foreign_keys = ON');
      }
    } catch (_) {
      await mediaRollback.rollback();
      rethrow;
    }
    // Keep the restore itself in the same auditable history as the export. It
    // is written only after the replacement transaction succeeds, so a failed
    // or rejected backup never claims to have restored anything.
    await recordBackupLog(
      uuid: _newUuid(),
      kind: 'full_restore',
      manifestJson: jsonEncode(snapshot['manifest']),
      status: 'restored',
    );
  }

  Future<_SnapshotMediaRollback> _applySnapshotMedia(Object? rawMedia) async {
    if (rawMedia == null) {
      return const _SnapshotMediaRollback(<String, List<int>?>{});
    }
    _validateSnapshotMedia(rawMedia);
    final media = rawMedia as List;
    final docs = await _applicationDocumentsDirectory();
    if (docs == null) {
      return const _SnapshotMediaRollback(<String, List<int>?>{});
    }
    final oldBytes = <String, List<int>?>{};
    final applied = <String>[];
    try {
      for (final item in media) {
        final entry = Map<Object?, Object?>.from(item as Map);
        final path = entry['path'] as String;
        final file = File(join(docs.path, path));
        oldBytes[path] = await file.exists() ? await file.readAsBytes() : null;
      }
      for (final item in media) {
        final entry = Map<Object?, Object?>.from(item as Map);
        final path = entry['path'] as String;
        final bytes = base64Decode(entry['bytes'] as String);
        final file = File(join(docs.path, path));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
        applied.add(path);
      }
    } catch (_) {
      await _restoreSnapshotMediaBytes(docs, oldBytes, applied);
      rethrow;
    }
    return _SnapshotMediaRollback(oldBytes, documents: docs);
  }

  Future<void> _restoreSnapshotMediaBytes(
    Directory docs,
    Map<String, List<int>?> oldBytes,
    Iterable<String> paths,
  ) async {
    for (final path in paths) {
      final file = File(join(docs.path, path));
      final bytes = oldBytes[path];
      if (bytes == null) {
        if (await file.exists()) await file.delete();
      } else {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      }
    }
  }

  static void _validateSnapshotMedia(Object? rawMedia) {
    if (rawMedia == null) return;
    if (rawMedia is! List) {
      throw const FormatException('Invalid snapshot media');
    }
    for (final item in rawMedia) {
      if (item is! Map) throw const FormatException('Invalid snapshot media');
      final path = item['path'];
      final encoded = item['bytes'];
      if (path is! String || encoded is! String || !_isSafeSnapshotPath(path)) {
        throw const FormatException('Invalid snapshot media entry');
      }
      try {
        base64Decode(encoded);
      } on FormatException {
        throw const FormatException('Invalid snapshot media bytes');
      }
    }
  }

  /// Pure database tests run without Flutter's path-provider plugin. The
  /// actual app always has it; treating the missing plugin as "no local media"
  /// keeps headless database tests independent of platform channels.
  static Future<Directory?> _applicationDocumentsDirectory() async {
    try {
      return await getApplicationDocumentsDirectory();
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> getDiscountsEnabled() async =>
      (await getSetting(settingDiscountsEnabled)) == '1';

  Future<int> getDiscountPercent(String key, {int fallback = 0}) async {
    final value = int.tryParse((await getSetting(key)) ?? '');
    return (value ?? fallback).clamp(0, 100);
  }

  Future<bool> getDiscountReasonRequired() async =>
      (await getSetting(settingDiscountReasonRequired)) == '1';

  Future<bool> getDiscountBelowCostAllowed() async =>
      (await getSetting(settingDiscountBelowCostAllowed)) == '1';

  Future<List<Map<String, dynamic>>> getDiscountReasons() async =>
      (await database).query('discount_reasons',
          where: 'active = 1', orderBy: 'name COLLATE NOCASE');

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

  Future<String?> _settingFromExecutor(
      DatabaseExecutor executor, String key) async {
    final rows = await executor.query('shop_settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final value = rows.first['value'];
    return value is String ? value : value?.toString();
  }

  Future<String> _tillCodeFromExecutor(DatabaseExecutor executor) async {
    final configured =
        (await _settingFromExecutor(executor, settingTillCode))?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return defaultTillCode(_workspaceKey);
  }

  Future<int> _vatRateFromExecutor(DatabaseExecutor executor) async {
    final parsed = int.tryParse(
        await _settingFromExecutor(executor, settingVatRate) ?? '');
    if (parsed == null || parsed < 0 || parsed > 100) {
      return _defaultVatRatePercent;
    }
    return parsed;
  }

  Future<int> _creditDefaultLimitFromExecutor(DatabaseExecutor executor) async {
    final parsed = int.tryParse(
        await _settingFromExecutor(executor, settingCreditDefaultLimitMinor) ??
            '');
    return parsed == null || parsed < 0 ? 0 : parsed;
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

  Future<int> getExpenseApprovalLimitMinor() async {
    final parsed = int.tryParse(
      await getSetting(settingExpenseApprovalLimitMinor) ?? '',
    );
    return parsed == null || parsed < 0 ? 500000 : parsed;
  }

  Future<void> setExpenseApprovalLimitMinor(int minorUnits) {
    if (minorUnits < 0) {
      throw ArgumentError.value(minorUnits, 'minorUnits');
    }
    return setSetting(settingExpenseApprovalLimitMinor, '$minorUnits');
  }

  // ---------------- Credit settings ----------------
  //
  // Selling on account is a money-adjacent capability and ships OFF (spec
  // D5). The default limit of zero means that even after the owner turns
  // credit on, nobody can take anything on account until they name a limit —

  /// Whether the shop sells on credit at all.
  Future<bool> getCreditEnabled() async =>
      (await getSetting(settingCreditEnabled)) == '1';

  Future<void> setCreditEnabled(bool enabled) =>
      setSetting(settingCreditEnabled, enabled ? '1' : '0');

  /// The limit a customer with no override of their own may owe. Zero is
  /// valid: it means nobody can owe anything until the owner names a figure -
  /// no silent default limit that a shop never agreed to.
  Future<int> getCreditDefaultLimit() async {
    final parsed =
        int.tryParse(await getSetting(settingCreditDefaultLimitMinor) ?? '');
    return parsed == null || parsed < 0 ? 0 : parsed;
  }

  Future<void> setCreditDefaultLimit(int minorUnits) {
    if (minorUnits < 0) {
      throw ArgumentError.value(
          minorUnits, 'minorUnits', 'must not be negative');
    }
    return setSetting(settingCreditDefaultLimitMinor, '$minorUnits');
  }

  /// What happens when a sale would pass the customer's limit: `block`
  /// (default) refuses the sale until a manager approves it; `warn` lets the
  /// cashier through once they have seen the warning.
  Future<String> getCreditLimitMode() async =>
      (await getSetting(settingCreditLimitMode)) == 'warn' ? 'warn' : 'block';

  Future<void> setCreditLimitMode(String mode) =>
      setSetting(settingCreditLimitMode, mode == 'warn' ? 'warn' : 'block');

  /// Whether a CASHIER (not the owner or a manager) may sell on account.
  /// Off by default; the owner turns it on for a till that deals in credit
  /// every day.
  Future<bool> getCreditCashiersAllowed() async =>
      (await getSetting(settingCreditCashiersAllowed)) == '1';

  Future<void> setCreditCashiersAllowed(bool allowed) =>
      setSetting(settingCreditCashiersAllowed, allowed ? '1' : '0');

  /// The text a payment reminder is built from. The shop can write their own;
  /// the default names the shop, the customer and the balance (model/credit.dart).
  Future<String> getCreditReminderTemplate() async {
    final raw = await getSetting(settingCreditReminderTemplate);
    final template = raw?.trim();
    if (template == null || template.isEmpty) return kDefaultReminderTemplate;
    return template;
  }

  Future<void> setCreditReminderTemplate(String template) =>
      setSetting(settingCreditReminderTemplate, template);

  /// The name a reminder or a statement cites. Empty when the shop never
  /// set one up (a till that sells before naming itself) — the template then
  /// reads naturally without it.
  Future<String> getShopName() async {
    final rows = await (await database)
        .query('owner', columns: <String>['shop_name'], limit: 1);
    return (rows.first['shop_name'] as String?) ?? '';
  }

  /// How a delivery prices what it brings.
  ///
  /// Weighted average is the default (spec D3): shelf + delivery blended,
  /// which is how a small shop reasons about the price of "the beer" rather
  /// than of this week's case. `last_cost` replaces the cost outright, for
  /// the shop that would rather see last Thursday's invoice figure.
  static const String settingCostingMode = 'costing_mode';

  Future<String> getCostingMode() async =>
      (await getSetting(settingCostingMode)) == 'last_cost'
          ? 'last_cost'
          : 'weighted_average';

  Future<void> setCostingMode(String mode) => setSetting(settingCostingMode,
      mode == 'last_cost' ? 'last_cost' : 'weighted_average');

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

  Future<void> _recordProductPriceIfChanged(
    DatabaseExecutor executor, {
    required int productId,
    required int costPrice,
    required int sellPrice,
    String? reason,
  }) async {
    final latest = await executor.query(
      'product_price_history',
      columns: ['cost_price', 'sell_price'],
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'recorded_at DESC, id DESC',
      limit: 1,
    );
    final changed = latest.isEmpty ||
        latest.first['cost_price'] != costPrice ||
        latest.first['sell_price'] != sellPrice;
    if (!changed) return;
    await executor.insert('product_price_history', <String, Object?>{
      'product_id': productId,
      'recorded_at': DateTime.now().toIso8601String(),
      'cost_price': costPrice,
      'sell_price': sellPrice,
      'reason': reason,
    });
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
      await _recordProductPriceIfChanged(db,
          productId: id,
          costPrice: p.costPrice.minorUnits,
          sellPrice: p.sellPrice.minorUnits,
          reason: 'created');
      return id;
    } else {
      final previous = await db.query('products',
          columns: [
            'cost_price',
            'sell_price',
            'track_expiry',
            'track_variants',
            'unit',
            'ml_per_kg',
            'stock_qty'
          ],
          where: 'id = ?',
          whereArgs: [p.id],
          limit: 1);
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
        final id = await db.insert('products', values);
        await _recordProductPriceIfChanged(db,
            productId: id,
            costPrice: p.costPrice.minorUnits,
            sellPrice: p.sellPrice.minorUnits,
            reason: 'restored');
        return id;
      }
      final changed = previous.isEmpty ||
          previous.first['cost_price'] != p.costPrice.minorUnits ||
          previous.first['sell_price'] != p.sellPrice.minorUnits;
      if (changed) {
        await _recordProductPriceIfChanged(db,
            productId: p.id!,
            costPrice: p.costPrice.minorUnits,
            sellPrice: p.sellPrice.minorUnits,
            reason: 'updated');
      }
      await _backfillExpiryBatchIfEnabled(db, p, previous);
      return p.id!;
    }
  }

  Future<void> _backfillExpiryBatchIfEnabled(
    DatabaseExecutor db,
    Product product,
    List<Map<String, dynamic>> previous,
  ) async {
    if (previous.isEmpty ||
        !product.trackExpiry ||
        (previous.first['track_expiry'] as num?)?.toInt() == 1 ||
        product.trackVariants ||
        product.unit.isMeasuredByWeight ||
        product.stockQty <= _qtyEpsilon) {
      return;
    }
    final existing = await db.query('stock_batches',
        columns: ['id'], where: 'product_id = ?', whereArgs: [product.id]);
    if (existing.isNotEmpty) return;
    // Unknown expiry is represented by the far-future sentinel. It is visible
    // as "Unknown" in batch views and is never accidentally treated as stale.
    await db.insert('stock_batches', {
      'uuid': _newUuid(),
      'product_id': product.id,
      'received_at': DateTime.now().toIso8601String(),
      'expires_at': '9999-12-31T23:59:59.999',
      'qty_remaining': product.stockQty,
      'unit_cost_minor': product.costPrice.minorUnits,
      'status': 'active',
    });
  }

  /// Same as [upsertProduct] but inside an already-open transaction, so a
  /// product row and its variants commit in one all-or-nothing unit. Without
  /// this a variant save that fails after the product insert leaves a product
  /// the editor still thinks is new — and the next Save inserts it again.
  Future<int> upsertProductInTransaction(Transaction txn, Product p) async {
    if (p.id == null) {
      final id = await txn.insert('products', p.toMap());
      await _recordProductPriceIfChanged(txn,
          productId: id,
          costPrice: p.costPrice.minorUnits,
          sellPrice: p.sellPrice.minorUnits,
          reason: 'created');
      return id;
    } else {
      final previous = await txn.query('products',
          columns: ['cost_price', 'sell_price'],
          where: 'id = ?',
          whereArgs: [p.id],
          limit: 1);
      final values = p.toMap();
      if (p.remoteId == null) values.remove('remote_id');
      final updated = await txn
          .update('products', values, where: 'id = ?', whereArgs: [p.id]);
      if (updated == 0) {
        values.remove('id');
        final id = await txn.insert('products', values);
        await _recordProductPriceIfChanged(txn,
            productId: id,
            costPrice: p.costPrice.minorUnits,
            sellPrice: p.sellPrice.minorUnits,
            reason: 'restored');
        return id;
      }
      if (previous.isEmpty ||
          previous.first['cost_price'] != p.costPrice.minorUnits ||
          previous.first['sell_price'] != p.sellPrice.minorUnits) {
        await _recordProductPriceIfChanged(txn,
            productId: p.id!,
            costPrice: p.costPrice.minorUnits,
            sellPrice: p.sellPrice.minorUnits,
            reason: 'updated');
      }
      return p.id!;
    }
  }

  Future<List<Map<String, dynamic>>> getProductPriceHistory(
    int productId, {
    DateTime? since,
    DateTime? until,
    int limit = 100,
  }) async {
    final where = <String>['product_id = ?'];
    final args = <Object?>[productId];
    if (since != null) {
      where.add('recorded_at >= ?');
      args.add(since.toIso8601String());
    }
    if (until != null) {
      where.add('recorded_at < ?');
      args.add(until.toIso8601String());
    }
    final rows = await (await database).query(
      'product_price_history',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'recorded_at DESC, id DESC',
      limit: limit.clamp(1, 500),
    );
    return rows.map(Map<String, dynamic>.from).toList();
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
          final id = await txn.insert('products', values);
          await _recordProductPriceIfChanged(
            txn,
            productId: id,
            costPrice: p.costPrice.minorUnits,
            sellPrice: p.sellPrice.minorUnits,
            reason: 'created',
          );
          continue;
        }
        if (p.remoteId == null) values.remove('remote_id');
        final updated = await txn
            .update('products', values, where: 'id = ?', whereArgs: [p.id]);
        if (updated == 0) {
          // Row not present locally (restore onto a fresh device): insert it.
          final id = await txn.insert('products', values);
          await _recordProductPriceIfChanged(
            txn,
            productId: id,
            costPrice: p.costPrice.minorUnits,
            sellPrice: p.sellPrice.minorUnits,
            reason: 'restored',
          );
          continue;
        }
        await _recordProductPriceIfChanged(
          txn,
          productId: p.id!,
          costPrice: p.costPrice.minorUnits,
          sellPrice: p.sellPrice.minorUnits,
          reason: 'updated',
        );
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
    Money? intendedTotal,
  }) async {
    await (await database).insert(
        'pending_payments',
        {
          'reference': reference,
          'phone_number': phoneNumber,
          'amount': amount.minorUnits,
          'tender_amount_minor': amount.minorUnits,
          'intended_total_minor': (intendedTotal ?? amount).minorUnits,
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

  Future<int> holdCart({
    required String uuid,
    required String staffName,
    int? staffId,
    required List<Map<String, Object?>> lines,
    int? customerId,
    Duration expiry = const Duration(hours: 24),
  }) async {
    if (lines.isEmpty) throw StateError('Cannot hold an empty cart');
    final now = DateTime.now();
    final db = await database;
    return db.transaction<int>((txn) async {
      final count = Sqflite.firstIntValue(await txn.rawQuery(
            "SELECT COUNT(*) FROM held_carts WHERE status = 'held'",
          )) ??
          0;
      if (count >= 10) {
        throw StateError('The till already has the maximum of 10 held sales');
      }
      final cartId = await txn.insert('held_carts', {
        'uuid': uuid,
        'staff_id': staffId,
        'staff_name': staffName,
        'created_at': now.toIso8601String(),
        'expires_at': now.add(expiry).toIso8601String(),
        'customer_id': customerId,
      });
      for (final line in lines) {
        await txn.insert('held_cart_lines', {
          'held_cart_id': cartId,
          ...line,
        });
      }
      return cartId;
    });
  }

  Future<List<Map<String, dynamic>>> getHeldCarts({DateTime? now}) async {
    final db = await database;
    await db.delete('held_carts',
        where: "status = 'held' AND expires_at <= ?",
        whereArgs: [(now ?? DateTime.now()).toIso8601String()]);
    return db.rawQuery('''
      SELECT c.*, cu.name AS customer_name, COUNT(l.id) AS line_count
      FROM held_carts c LEFT JOIN held_cart_lines l ON l.held_cart_id = c.id
      LEFT JOIN customers cu ON cu.id = c.customer_id
      WHERE c.status = 'held'
      GROUP BY c.id ORDER BY c.created_at DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getHeldCartLines(int cartId) async =>
      (await database).query('held_cart_lines',
          where: 'held_cart_id = ?', whereArgs: [cartId], orderBy: 'id');

  Future<void> deleteHeldCart(int cartId) async {
    await (await database).transaction((txn) async {
      await txn.delete('held_cart_lines',
          where: 'held_cart_id = ?', whereArgs: [cartId]);
      await txn.delete('held_carts', where: 'id = ?', whereArgs: [cartId]);
    });
  }

  Future<int> recordReceiptShare({
    required String uuid,
    required int saleId,
    String? token,
    String? url,
    String? recipientMasked,
    String? expiresAt,
  }) async =>
      (await database).insert('receipt_shares', {
        'uuid': uuid,
        'sale_id': saleId,
        'token': token,
        'url': url,
        'recipient_masked': recipientMasked,
        'created_at': DateTime.now().toIso8601String(),
        'expires_at': expiresAt,
      });

  Future<List<Map<String, dynamic>>> getReceiptShares(int saleId) async =>
      (await database).query('receipt_shares',
          where: 'sale_id = ?',
          whereArgs: [saleId],
          orderBy: 'created_at DESC');

  Future<void> revokeReceiptShare(int id) async => (await database).update(
        'receipt_shares',
        {
          'status': 'revoked',
          'revoked_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<int> recordDrawerEvent({
    required String uuid,
    required String eventType,
    required String staffName,
    String? reason,
    int? shiftId,
    int? staffId,
    int? saleId,
    String? approvedBy,
    bool success = false,
  }) async {
    if (uuid.trim().isEmpty) throw ArgumentError.value(uuid, 'uuid');
    if (!<String>{'sale', 'no_sale', 'refund', 'manual'}.contains(eventType)) {
      throw StateError('Unknown drawer event');
    }
    return (await database).insert('drawer_events', {
      'uuid': uuid,
      'shift_id': shiftId,
      'event_type': eventType,
      'reason': reason,
      'staff_id': staffId,
      'staff_name': staffName,
      'sale_id': saleId,
      'approved_by': approvedBy,
      'created_at': DateTime.now().toIso8601String(),
      'success': success ? 1 : 0,
    });
  }

  Future<List<Map<String, dynamic>>> getDrawerEvents({
    int? shiftId,
    int? staffId,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (shiftId != null) {
      where.add('shift_id = ?');
      args.add(shiftId);
    }
    if (staffId != null) {
      where.add('staff_id = ?');
      args.add(staffId);
    }
    return (await database).query(
      'drawer_events',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedDrawerEvents() async {
    return (await database).query(
      'drawer_events',
      where: 'synced_to_backend = 0',
      orderBy: 'created_at ASC, id ASC',
      limit: 500,
    );
  }

  Future<void> markDrawerEventsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    await (await database).rawUpdate(
      'UPDATE drawer_events SET synced_to_backend = 1 WHERE id IN (${List.filled(ids.length, '?').join(',')})',
      ids,
    );
  }

  Future<int> recordBackupLog({
    required String uuid,
    required String kind,
    String? path,
    int clearBytes = 0,
    String? manifestJson,
    String status = 'written',
  }) async {
    return (await database).insert('backup_log', {
      'uuid': uuid,
      'kind': kind,
      'path': path,
      'created_at': DateTime.now().toIso8601String(),
      'clear_bytes': clearBytes,
      'manifest_json': manifestJson,
      'status': status,
    });
  }

  Future<List<Map<String, dynamic>>> getBackupLog({int limit = 50}) async =>
      (await database).query(
        'backup_log',
        orderBy: 'created_at DESC',
        limit: limit,
      );

  Future<int> countBackupLog() async {
    final rows =
        await (await database).rawQuery('SELECT COUNT(*) AS c FROM backup_log');
    return (rows.single['c'] as num).toInt();
  }

  Future<void> upsertIncomingPayment(IncomingPayment payment) async {
    await (await database).insert(
      'incoming_payments',
      {
        'remote_id': payment.remoteId,
        'trans_id': payment.transactionId,
        'amount_minor': payment.amount.minorUnits,
        'payer_masked': payment.payerMasked,
        'received_at': payment.receivedAt.toIso8601String(),
        'status': payment.status,
        'claimed_at': payment.claimedAt?.toIso8601String(),
        'claimed_by': payment.claimedBy,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<IncomingPayment>> getIncomingPayments({
    String? status,
    int limit = 200,
  }) async {
    final rows = await (await database).query(
      'incoming_payments',
      where: status == null ? null : 'status = ?',
      whereArgs: status == null ? null : [status],
      orderBy: 'received_at DESC',
      limit: limit,
    );
    return rows.map(IncomingPayment.fromMap).toList();
  }

  Future<int> countIncomingPayments({String? status}) async {
    final rows = await (await database).rawQuery(
      status == null
          ? 'SELECT COUNT(*) AS c FROM incoming_payments'
          : 'SELECT COUNT(*) AS c FROM incoming_payments WHERE status = ?',
      status == null ? const [] : [status],
    );
    return (rows.single['c'] as num).toInt();
  }

  /// Durable claim work created after an offline till sale. A claim is kept
  /// separate from the sale because the sale is already valid local ledger
  /// data; only the server-side ownership of the incoming payment is pending.
  Future<void> recordIncomingPaymentClaim({
    required String remoteId,
    required int saleId,
    required String saleUuid,
    String status = 'pending',
    String? reason,
  }) async {
    final now = DateTime.now().toIso8601String();
    await (await database).insert(
      'incoming_payment_claims',
      {
        'remote_id': remoteId,
        'sale_id': saleId,
        'sale_uuid': saleUuid,
        'status': status,
        'reason': reason,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingIncomingPaymentClaims() async =>
      (await database).query(
        'incoming_payment_claims',
        where: "status = 'pending'",
        orderBy: 'created_at ASC',
        limit: 200,
      );

  Future<int> countPendingIncomingPaymentClaims() async {
    final rows = await (await database).rawQuery(
      "SELECT COUNT(*) AS c FROM incoming_payment_claims WHERE status = 'pending'",
    );
    return (rows.single['c'] as num).toInt();
  }

  Future<void> resolveIncomingPaymentClaim(String remoteId) async {
    await (await database).delete(
      'incoming_payment_claims',
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
  }

  Future<void> markIncomingPaymentClaimDisputed(
    String remoteId,
    String reason,
  ) async {
    await (await database).update(
      'incoming_payment_claims',
      {
        'status': 'disputed',
        'reason': reason,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
    await (await database).update(
      'incoming_payments',
      {
        'status': 'disputed',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingPayments() async =>
      (await database).query('pending_payments', orderBy: 'created_at ASC');

  Future<int> countPendingPayments() async {
    final rows = await (await database).rawQuery(
      'SELECT COUNT(*) AS c FROM pending_payments',
    );
    return (rows.single['c'] as num).toInt();
  }

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

  Future<void> adjustStock(
    StockAdjustment adj, {
    int? staffId,
    StockMovementType movementType = StockMovementType.adjustment,
  }) async {
    if (movementType == StockMovementType.writeoff && adj.delta >= 0) {
      throw ArgumentError('A stock write-off must reduce stock');
    }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('products',
          where: 'id = ?', whereArgs: [adj.productId], limit: 1);
      if (rows.isEmpty) throw StateError('Product not found');
      final currentStock = (rows.first['stock_qty'] as num).toDouble();
      final unitCostMinor = (rows.first['cost_price'] as num?)?.toInt() ?? 0;
      if (currentStock + adj.delta < 0) {
        throw StateError('Stock cannot go below zero');
      }
      final adjustmentId = await txn.insert('stock_adjustments', {
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
        type: movementType,
        qtyDelta: adj.delta.toDouble(),
        unitCostMinor: unitCostMinor,
        referenceType: 'adjustment',
        staffId: staffId,
        staffName: adj.staffName,
        note: adj.reason,
        balanceAfter: balance,
      );
      if (adj.delta != 0) {
        await _appendFinancialEvent(
          txn: txn,
          eventType: movementType == StockMovementType.writeoff
              ? 'stock_writeoff'
              : 'stock_adjustment',
          sourceType: movementType == StockMovementType.writeoff
              ? 'stock_writeoff'
              : 'stock_adjustment',
          sourceId: adjustmentId,
          occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
          inventoryDeltaMilliunits: (adj.delta * 1000).round(),
          metadata: <String, Object?>{
            'product_id': adj.productId,
            'reason': adj.reason,
          },
        );
      }
    });
  }

  Future<List<StockAdjustment>> getRecentAdjustments({int limit = 30}) async {
    final rows = await (await database)
        .query('stock_adjustments', orderBy: 'created_at DESC', limit: limit);
    return rows.map((r) => StockAdjustment.fromMap(r)).toList();
  }

  /// Converts stock from one catalogue unit into another atomically.
  ///
  /// The source and output products are deliberately ordinary products in the
  /// shared catalogue: a Duka can therefore turn bulk sugar into packets,
  /// while sales, receipts, analytics and sync continue to use the same
  /// engines. Both movements are append-only and carry the calculated output
  /// cost, so the operation remains explainable after either product is
  /// renamed.
  Future<void> repackStock({
    required int sourceProductId,
    required int outputProductId,
    required double sourceQty,
    required double outputQty,
    required String staffName,
    int? staffId,
    String note = 'Repack',
  }) async {
    if (sourceProductId == outputProductId) {
      throw ArgumentError('Source and output products must differ');
    }
    if (!sourceQty.isFinite || sourceQty <= 0) {
      throw ArgumentError.value(sourceQty, 'sourceQty');
    }
    if (!outputQty.isFinite || outputQty <= 0) {
      throw ArgumentError.value(outputQty, 'outputQty');
    }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id IN (?, ?) AND active = 1',
        whereArgs: [sourceProductId, outputProductId],
      );
      if (rows.length != 2) throw StateError('Repack products were not found');
      final source = rows.firstWhere((row) => row['id'] == sourceProductId);
      final output = rows.firstWhere((row) => row['id'] == outputProductId);
      if ((source['track_variants'] as num?)?.toInt() == 1 ||
          (output['track_variants'] as num?)?.toInt() == 1) {
        throw StateError('Repack variant stock at the variant level');
      }
      final sourceStock = (source['stock_qty'] as num).toDouble();
      if (sourceQty > sourceStock + _qtyEpsilon) {
        throw StateError(
            'Repack cannot use more source stock than is available');
      }
      final sourceCostMinor = (source['cost_price'] as num?)?.toInt() ?? 0;
      final incomingOutputCostMinor =
          (sourceCostMinor * sourceQty / outputQty).round();
      final outputStock = (output['stock_qty'] as num).toDouble();
      final outputCostMinor = _weightedAverageCost(
        onHandMinor: (output['cost_price'] as num?)?.toInt() ?? 0,
        onHandQty: outputStock,
        incomingQty: outputQty,
        incomingMinor: incomingOutputCostMinor,
      );
      final sourceBalance = sourceStock - sourceQty;
      final outputBalance = outputStock + outputQty;
      final operationNote = '${note.trim().isEmpty ? 'Repack' : note.trim()} '
          '($sourceProductId → $outputProductId)';

      await txn.rawUpdate(
        'UPDATE products SET stock_qty = ?, updated_at = ? WHERE id = ?',
        [sourceBalance, DateTime.now().toIso8601String(), sourceProductId],
      );
      await txn.rawUpdate(
        'UPDATE products SET stock_qty = ?, cost_price = ?, updated_at = ? '
        'WHERE id = ?',
        [
          outputBalance,
          outputCostMinor,
          DateTime.now().toIso8601String(),
          outputProductId,
        ],
      );
      await _writeStockMovement(
        txn,
        productId: sourceProductId,
        type: StockMovementType.repack,
        qtyDelta: -sourceQty,
        unitCostMinor: sourceCostMinor,
        referenceType: 'stock_repack',
        referenceId: sourceProductId,
        staffId: staffId,
        staffName: staffName,
        note: operationNote,
        balanceAfter: sourceBalance,
      );
      await _writeStockMovement(
        txn,
        productId: outputProductId,
        type: StockMovementType.repack,
        qtyDelta: outputQty,
        unitCostMinor: outputCostMinor,
        referenceType: 'stock_repack',
        referenceId: sourceProductId,
        staffId: staffId,
        staffName: staffName,
        note: operationNote,
        balanceAfter: outputBalance,
      );
      await _appendFinancialEvent(
        txn: txn,
        eventType: 'stock_repack',
        sourceType: 'stock_repack',
        sourceId: sourceProductId,
        occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
        metadata: <String, Object?>{
          'source_product_id': sourceProductId,
          'output_product_id': outputProductId,
          'source_qty': sourceQty,
          'output_qty': outputQty,
          'output_cost_minor': incomingOutputCostMinor,
          'output_weighted_cost_minor': outputCostMinor,
        },
      );
    });
  }

  // ---------------- Sales (atomic checkout) ----------------

  static const Set<String> _laybyPaymentMethods = {
    'cash',
    'card',
    'bank_transfer',
    'mobile_money_manual',
    'mpesa',
    'mpesa_till',
  };

  Future<int> createLayby({
    required int customerId,
    required List<SaleItem> items,
    required Money deposit,
    required String depositMethod,
    required DateTime dueAt,
    required String staffName,
    String? depositReference,
    int? staffId,
  }) async {
    if (items.isEmpty ||
        items.any((item) => item.qty <= 0 || !item.qty.isFinite)) {
      throw StateError('A lay-by must contain positive quantities');
    }
    if (!_laybyPaymentMethods.contains(depositMethod)) {
      throw StateError('Unsupported lay-by payment method');
    }
    if (dueAt.isBefore(DateTime.now())) {
      throw StateError('Due date must be in the future');
    }
    final total = sumMoney(items.map((item) => item.total));
    if (deposit.isZero || deposit.isNegative || deposit > total) {
      throw StateError(
          'Deposit must be positive and no greater than the total');
    }
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final eventAt = DateTime.now().toUtc().toIso8601String();
    return db.transaction<int>((txn) async {
      final customer = await txn.query('customers',
          where: 'id = ? AND active = 1', whereArgs: [customerId], limit: 1);
      if (customer.isEmpty) {
        throw StateError('Customer not found');
      }
      final productRows = <int, Map<String, dynamic>>{};
      final variantRows = <int, Map<String, dynamic>>{};
      for (final item in items) {
        final rows = await txn.query('products',
            where: 'id = ?', whereArgs: [item.productId], limit: 1);
        if (rows.isEmpty) {
          throw StateError('Product not found: ${item.productName}');
        }
        productRows[item.productId] = rows.first;
        final variantId = item.variantId;
        if (variantId != null) {
          final variants = await txn.query('product_variants',
              where: 'id = ? AND product_id = ?',
              whereArgs: [variantId, item.productId],
              limit: 1);
          if (variants.isEmpty) {
            throw StateError('Variant not found: ${item.variantName}');
          }
          variantRows[variantId] = variants.first;
        }
      }
      for (final item in items) {
        final product = productRows[item.productId]!;
        final qty = item.qty;
        if (item.variantId != null) {
          final variant = variantRows[item.variantId]!;
          final available = (variant['stock_qty'] as num).toDouble() -
              ((variant['reserved_qty'] as num?)?.toDouble() ?? 0);
          if (available + _volumeTolerance < qty) {
            throw StateError('Not enough stock for ${item.productName}');
          }
          await txn.rawUpdate(
              'UPDATE product_variants SET reserved_qty = reserved_qty + ? WHERE id = ?',
              [qty, item.variantId]);
        } else {
          final available = (product['stock_qty'] as num).toDouble() -
              ((product['reserved_qty'] as num?)?.toDouble() ?? 0);
          if (available + _volumeTolerance < qty) {
            throw StateError('Not enough stock for ${item.productName}');
          }
        }
        await txn.rawUpdate(
            'UPDATE products SET reserved_qty = reserved_qty + ? WHERE id = ?',
            [qty, item.productId]);
      }
      final laybyId = await txn.insert('laybys', {
        'uuid': _newUuid(),
        'customer_id': customerId,
        'status': LaybyStatus.open.wire,
        'total_minor': total.minorUnits,
        'paid_minor': deposit.minorUnits,
        'due_at': dueAt.toIso8601String(),
        'created_at': now,
        'staff_id': staffId,
        'staff_name': staffName,
        'synced_to_backend': 0,
      });
      for (final item in items) {
        await txn.insert('layby_items', {
          'layby_id': laybyId,
          'product_id': item.productId,
          'variant_id': item.variantId,
          'product_name': item.productName,
          'variant_name': item.variantName,
          'qty': item.qty,
          'unit_price_minor': item.unitPrice.minorUnits,
          'unit_cost_minor': item.unitCost.minorUnits,
          'discount_minor': item.discount.minorUnits,
          'total_minor': item.total.minorUnits,
        });
      }
      await txn.insert('layby_payments', {
        'layby_id': laybyId,
        'method': depositMethod,
        'amount_minor': deposit.minorUnits,
        'direction': 'in',
        'reference': depositReference,
        'created_at': now,
        'staff_id': staffId,
        'staff_name': staffName,
      });
      await _appendFinancialEvent(
        txn: txn,
        eventType: 'layby_deposit',
        sourceType: 'layby',
        sourceId: laybyId,
        occurredAtUtc: eventAt,
        cashInMinor: deposit.minorUnits,
        customerDepositDeltaMinor: deposit.minorUnits,
        metadata: {'payment_method': depositMethod},
      );
      return laybyId;
    });
  }

  Future<Layby?> getLayby(int id) async {
    final db = await database;
    final rows =
        await db.query('laybys', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final items = await db.query('layby_items',
        where: 'layby_id = ?', whereArgs: [id], orderBy: 'id ASC');
    final payments = await db.query('layby_payments',
        where: 'layby_id = ?', whereArgs: [id], orderBy: 'id ASC');
    return Layby.fromMap(rows.first,
        items: items.map(LaybyItem.fromMap).toList(),
        payments: payments.map(LaybyPayment.fromMap).toList());
  }

  Future<List<Layby>> getLaybys({int? customerId, LaybyStatus? status}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (customerId != null) {
      where.add('customer_id = ?');
      args.add(customerId);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status.wire);
    }
    final rows = await db.query('laybys',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'created_at DESC');
    final result = <Layby>[];
    for (final row in rows) {
      final id = (row['id'] as num).toInt();
      result.add(Layby.fromMap(row,
          items: (await db
                  .query('layby_items', where: 'layby_id = ?', whereArgs: [id]))
              .map(LaybyItem.fromMap)
              .toList(),
          payments: (await db.query('layby_payments',
                  where: 'layby_id = ?', whereArgs: [id]))
              .map(LaybyPayment.fromMap)
              .toList()));
    }
    return result;
  }

  /// Returns complete lay-by snapshots for the offline sync queue. A lay-by is
  /// synced as one document so an admin or another till can see its current
  /// status together with the immutable item and payment history.
  Future<List<Map<String, dynamic>>> getUnsyncedLaybys(
      {int limit = 200}) async {
    final db = await database;
    final rows = await db.query('laybys',
        where: 'synced_to_backend = 0', orderBy: 'id ASC', limit: limit);
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final id = (row['id'] as num).toInt();
      final customerRows = await db.query('customers',
          columns: ['uuid'],
          where: 'id = ?',
          whereArgs: [row['customer_id']],
          limit: 1);
      final items = await db.query('layby_items',
          where: 'layby_id = ?', whereArgs: [id], orderBy: 'id ASC');
      final payments = await db.query('layby_payments',
          where: 'layby_id = ?', whereArgs: [id], orderBy: 'id ASC');
      result.add({
        ...row,
        'customer_uuid':
            customerRows.isEmpty ? null : customerRows.first['uuid'],
        'items': items,
        'payments': payments,
      });
    }
    return result;
  }

  Future<void> markLaybysSynced(Iterable<int> ids) async {
    final values = ids.toList();
    if (values.isEmpty) return;
    final db = await database;
    await db.update('laybys', {'synced_to_backend': 1},
        where: 'id IN (${List.filled(values.length, '?').join(',')})',
        whereArgs: values);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedExchanges(
      {int limit = 200}) async {
    final db = await database;
    return db.query('exchanges',
        where: 'synced_to_backend = 0', orderBy: 'id ASC', limit: limit);
  }

  Future<void> markExchangesSynced(Iterable<int> ids) async {
    final values = ids.toList();
    if (values.isEmpty) return;
    final db = await database;
    await db.update('exchanges', {'synced_to_backend': 1},
        where: 'id IN (${List.filled(values.length, '?').join(',')})',
        whereArgs: values);
  }

  Future<void> addLaybyPayment({
    required int laybyId,
    required Money amount,
    required String method,
    required String staffName,
    String? reference,
    int? staffId,
  }) async {
    if (!_laybyPaymentMethods.contains(method) ||
        amount.isZero ||
        amount.isNegative) {
      throw StateError('Invalid lay-by payment');
    }
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query('laybys',
          where: 'id = ?', whereArgs: [laybyId], limit: 1);
      if (rows.isEmpty || rows.first['status'] != LaybyStatus.open.wire) {
        throw StateError('Lay-by is not open');
      }
      final balance = (rows.first['total_minor'] as num).toInt() -
          (rows.first['paid_minor'] as num).toInt();
      if (amount.minorUnits > balance) {
        throw StateError('Payment exceeds lay-by balance');
      }
      await txn.insert('layby_payments', {
        'layby_id': laybyId,
        'method': method,
        'amount_minor': amount.minorUnits,
        'direction': 'in',
        'reference': reference,
        'created_at': now,
        'staff_id': staffId,
        'staff_name': staffName
      });
      await txn.rawUpdate(
          'UPDATE laybys SET paid_minor = paid_minor + ?, synced_to_backend = 0 WHERE id = ?',
          [amount.minorUnits, laybyId]);
      await _appendFinancialEvent(
          txn: txn,
          eventType: 'layby_payment',
          sourceType: 'layby',
          sourceId: laybyId,
          occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
          cashInMinor: amount.minorUnits,
          customerDepositDeltaMinor: amount.minorUnits,
          metadata: {'payment_method': method});
    });
  }

  Future<void> cancelLayby(
      {required int laybyId,
      required String staffName,
      int? staffId,
      bool expired = false,
      String refundMethod = 'cash',
      String? refundReference}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query('laybys',
          where: 'id = ?', whereArgs: [laybyId], limit: 1);
      if (rows.isEmpty || rows.first['status'] != LaybyStatus.open.wire) {
        throw StateError('Lay-by is not open');
      }
      final items = await txn
          .query('layby_items', where: 'layby_id = ?', whereArgs: [laybyId]);
      for (final item in items) {
        final qty = (item['qty'] as num).toDouble();
        await txn.rawUpdate(
            'UPDATE products SET reserved_qty = MAX(0, reserved_qty - ?) WHERE id = ?',
            [qty, item['product_id']]);
        if (item['variant_id'] != null) {
          await txn.rawUpdate(
              'UPDATE product_variants SET reserved_qty = MAX(0, reserved_qty - ?) WHERE id = ?',
              [qty, item['variant_id']]);
        }
      }
      final paid = (rows.first['paid_minor'] as num).toInt();
      if (paid > 0) {
        await txn.insert('layby_payments', {
          'layby_id': laybyId,
          'method': refundMethod,
          'amount_minor': paid,
          'direction': 'out',
          'reference': refundReference,
          'created_at': now,
          'staff_id': staffId,
          'staff_name': staffName
        });
      }
      await txn.update(
          'laybys',
          {
            'status':
                expired ? LaybyStatus.expired.wire : LaybyStatus.cancelled.wire,
            'cancelled_at': now,
            'synced_to_backend': 0
          },
          where: 'id = ?',
          whereArgs: [laybyId]);
      await _appendFinancialEvent(
          txn: txn,
          eventType: 'layby_cancel',
          sourceType: 'layby',
          sourceId: laybyId,
          occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
          cashOutMinor: paid,
          customerDepositDeltaMinor: -paid,
          metadata: {'expired': expired});
    });
  }

  Future<int> expireDueLaybys(
      {DateTime? now, required String staffName, int? staffId}) async {
    final due = now ?? DateTime.now();
    final open = await getLaybys(status: LaybyStatus.open);
    var count = 0;
    for (final layby in open) {
      if (!DateTime.parse(layby.dueAt).isAfter(due)) {
        await cancelLayby(
            laybyId: layby.id,
            staffName: staffName,
            staffId: staffId,
            expired: true);
        count++;
      }
    }
    return count;
  }

  Future<int> completeLayby(int laybyId,
      {required String staffName, int? staffId}) async {
    final layby = await getLayby(laybyId);
    if (layby == null || !layby.isOpen || layby.balance != Money.zero) {
      throw StateError('Lay-by is not ready for completion');
    }
    final items = layby.items
        .map((item) => SaleItem(
            saleId: 0,
            productId: item.productId,
            productName: item.productName,
            qty: item.qty,
            unitPrice: item.unitPrice,
            unitCost: item.unitCost,
            discount: item.discount,
            variantId: item.variantId,
            variantName: item.variantName))
        .toList();
    return recordSale(
        staffName: staffName,
        staffId: staffId,
        items: items,
        paymentMethod: 'layby',
        customerId: layby.customerId,
        laybyId: laybyId,
        amountTendered: layby.total);
  }

  /// Completes a Fashion exchange as one SQLite transaction: the original
  /// goods return, the replacement sale, the exchange-credit tender and any
  /// cash difference either all commit or all roll back.
  Future<int> recordExchange({
    required Sale originalSale,
    required List<ReturnLineDraft> returnedLines,
    required List<SaleItem> replacementItems,
    required String reason,
    required String staffName,
    String paymentMethod = 'cash',
    String? paymentReference,
    int? staffId,
  }) async {
    if (originalSale.id == null ||
        returnedLines.isEmpty ||
        replacementItems.isEmpty) {
      throw StateError(
          'An exchange needs a sale, return lines and replacement lines');
    }
    final replacementTotal =
        sumMoney(replacementItems.map((item) => item.total));
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return db.transaction<int>((txn) async {
      final existing = await txn.query('exchanges',
          where: 'original_sale_id = ? AND status = ?',
          whereArgs: [originalSale.id, 'completed'],
          limit: 1);
      if (existing.isNotEmpty) {
        throw StateError('That sale already has an exchange');
      }

      final exchangeId = await txn.insert('exchanges', {
        'uuid': _newUuid(),
        'original_sale_id': originalSale.id,
        'status': 'processing',
        'returned_total_minor': 0,
        'replacement_total_minor': replacementTotal.minorUnits,
        'difference_minor': 0,
        'difference_direction': 'even',
        'reason': reason.trim(),
        'staff_id': staffId,
        'staff_name': staffName,
        'created_at': now,
        'synced_to_backend': 0,
      });

      final returnId = await recordReturn(
        sale: originalSale,
        lines: returnedLines,
        reason: reason,
        kind: 'exchange',
        refundMethod: 'exchange_credit',
        staffName: staffName,
        staffId: staffId,
        existingTransaction: txn,
      );
      final returnRows = await txn.query('sale_returns',
          columns: ['total'], where: 'id = ?', whereArgs: [returnId], limit: 1);
      final returnedTotal = (returnRows.first['total'] as num).toInt();
      final exchangeCredit = returnedTotal < replacementTotal.minorUnits
          ? returnedTotal
          : replacementTotal.minorUnits;
      final difference = (replacementTotal.minorUnits - returnedTotal).abs();
      final direction = replacementTotal.minorUnits > returnedTotal
          ? 'customer_pays'
          : replacementTotal.minorUnits < returnedTotal
              ? 'customer_receives'
              : 'even';
      final externalAmount = replacementTotal.minorUnits > returnedTotal
          ? replacementTotal.minorUnits - returnedTotal
          : 0;
      final tenders = <SaleTender>[
        if (exchangeCredit > 0)
          SaleTender(
              method: 'exchange_credit',
              amount: Money.fromMinor(exchangeCredit),
              tendered: Money.fromMinor(exchangeCredit)),
        if (externalAmount > 0)
          SaleTender(
              method: paymentMethod,
              amount: Money.fromMinor(externalAmount),
              tendered: Money.fromMinor(externalAmount),
              reference: paymentReference),
      ];
      final replacementSaleId = await recordSale(
        staffName: staffName,
        staffId: staffId,
        items: replacementItems,
        paymentMethod: tenders.length == 1 ? tenders.single.method : 'split',
        paymentReference: paymentReference,
        tenders: tenders,
        existingTransaction: txn,
      );

      // The return initially records all returned value as exchange credit.
      // Reconcile that allocation to the actual replacement value, then make
      // any lower-price difference an explicit cash refund.
      final allocations = await txn.query('sale_return_refunds',
          where: 'return_id = ?', whereArgs: [returnId], orderBy: 'id ASC');
      if (allocations.isNotEmpty) {
        await txn.update('sale_return_refunds',
            {'amount_minor': exchangeCredit, 'method': 'exchange_credit'},
            where: 'id = ?', whereArgs: [allocations.first['id']]);
      }
      if (returnedTotal > replacementTotal.minorUnits) {
        await txn.insert('sale_return_refunds', {
          'return_id': returnId,
          'sale_payment_id': null,
          'method': 'cash',
          'amount_minor': returnedTotal - replacementTotal.minorUnits,
          'reference': paymentReference,
        });
        await _appendFinancialEvent(
          txn: txn,
          eventType: 'exchange_difference',
          sourceType: 'exchange',
          sourceId: exchangeId,
          occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
          cashOutMinor: returnedTotal - replacementTotal.minorUnits,
          metadata: {
            'return_id': returnId,
            'replacement_sale_id': replacementSaleId
          },
        );
      }
      await txn.update(
          'exchanges',
          {
            'return_id': returnId,
            'replacement_sale_id': replacementSaleId,
            'status': 'completed',
            'returned_total_minor': returnedTotal,
            'replacement_total_minor': replacementTotal.minorUnits,
            'difference_minor': difference,
            'difference_direction': direction,
            'synced_to_backend': 0,
          },
          where: 'id = ?',
          whereArgs: [exchangeId]);
      return replacementSaleId;
    });
  }

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
    List<SaleTender>? tenders,
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

    /// The customer taking the goods on account, for a `credit` sale.
    ///
    /// Required for, and ignored without, [paymentMethod] `credit`. The charge
    /// lands on the customer's ledger inside the SAME transaction as the sale,
    /// so a crash can never leave goods gone and nobody owing them.
    int? customerId,

    /// The manager or owner who approved an over-limit credit sale, when one
    /// has approved it. Their presence is what permits the sale to exceed the
    /// limit; without it the sale is refused.
    int? creditApprovedBy,
    int? discountApprovedBy,
    int? orderDiscountReasonId,
    int? laybyId,
    DatabaseExecutor? existingTransaction,
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
    // The cart is keyed on (product, portion), so a single bottle can appear as
    // several lines (e.g. one full + one half). Stock is therefore accumulated
    // per product before the availability check instead of rejecting repeats.
    //
    // The accumulation happens inside the transaction, below, because a measured
    // pour is only a fraction once you know how big the container is.
    final db = existingTransaction == null ? await database : null;
    // Every amount is quantised as it is accumulated, so the stored total is
    // exactly the sum of the stored line amounts and `change` is a real number
    // of shillings rather than a floating-point artefact.
    // Integer cents throughout: each line is scaled once (which rounds), and
    // the sums below are exact integer additions. The recorded total is
    // therefore always exactly the sum of the recorded line amounts.
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
    // A credit sale is paid with a promise. The tender is by definition
    // nothing, because the money has not moved; setting it here (rather than
    // letting `amountTendered ?? total` imply it) keeps the change arithmetic
    // honest and the payment row's amount at the full sale.
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
    // Resolved before the transaction opens: reads that touch the database must
    // not happen inside the transaction, or sqflite_ffi deadlocks on a read
    // inside a write transaction.
    final tillCode = existingTransaction == null
        ? await getTillCode()
        : await _tillCodeFromExecutor(existingTransaction);
    final vatRatePercent = existingTransaction == null
        ? await getVatRatePercent()
        : await _vatRateFromExecutor(existingTransaction);
    final taxRuleId = existingTransaction == null
        ? await getSetting(settingTaxRuleId)
        : await _settingFromExecutor(existingTransaction, settingTaxRuleId);
    final taxRuleVersion = int.tryParse(existingTransaction == null
        ? await getSetting(settingTaxRuleVersion) ?? ''
        : await _settingFromExecutor(
                existingTransaction, settingTaxRuleVersion) ??
            '');
    // The shop default a customer's own null limit falls back to, read here
    // for the same reason: not inside the transaction.
    final defaultLimitMinor = existingTransaction == null
        ? await getCreditDefaultLimit()
        : await _creditDefaultLimitFromExecutor(existingTransaction);

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
      // A line's fraction of its container — the shared rule, so a sale and a
      // return agree on what a portion of a bottle is.
      double portionFactor(SaleItem item, double containerMl) =>
          _portionFactor(item, containerMl);

      // Read every product this sale touches once: its stock is needed for the
      // availability check, its container size for the fraction, and its tax
      // class for the line's VAT snapshot.
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
          if (available - reserved + own + _volumeTolerance < entry.value) {
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
          final available = stockByProduct[entry.key]! -
              (reservedByProduct[entry.key] ?? 0) +
              (ownReservedByProduct[entry.key] ?? 0);
          if (available + _volumeTolerance < entry.value) {
            final offending =
                items.firstWhere((it) => it.productId == entry.key);
            throw StateError('Not enough stock for ${offending.productName}');
          }
        }
      }

      // Dated stock is a separate availability rule from the aggregate
      // product balance: an expired bottle must never be sold just because
      // the cached balance still includes it. Allocate oldest-first and keep
      // the rows available for the sale-item audit links below.
      final batchesByProduct = <int, List<Map<String, dynamic>>>{};
      final expiryKeys = <int, double>{
        ...directUnitsByProduct,
        for (final entry in requiredByVariant.entries) -entry.key: entry.value,
      };
      for (final entry in expiryKeys.entries) {
        final productId = entry.key < 0
            ? variantRowsById[-entry.key]!['product_id'] as int
            : entry.key;
        if (trackExpiryByProduct[productId] != true) continue;
        final variantId = entry.key < 0 ? -entry.key : null;
        final batchRows = await txn.query(
          'stock_batches',
          where: variantId == null
              ? 'product_id = ? AND variant_id IS NULL AND qty_remaining > 0 AND expires_at >= ?'
              : 'product_id = ? AND variant_id = ? AND qty_remaining > 0 AND expires_at >= ?',
          whereArgs: variantId == null
              ? [productId, now]
              : [productId, variantId, now],
          orderBy: 'expires_at ASC, id ASC',
        );
        final rows = <Map<String, dynamic>>[
          for (final row in batchRows) Map<String, dynamic>.from(row),
        ];
        final available = rows.fold<double>(
            0, (sum, row) => sum + (row['qty_remaining'] as num).toDouble());
        if (available + _volumeTolerance < entry.value) {
          final offending = items.firstWhere((it) => it.productId == entry.key);
          throw StateError(
              'Not enough unexpired stock for ${offending.productName}');
        }
        batchesByProduct[entry.key] = rows;
      }

      // Credit: the promise being taken, and the customer who will owe it.
      //
      // Read and checked inside the transaction, against the balance AS THE
      // LEDGER HAS IT NOW — a balance read before the transaction opened would
      // let two simultaneous sales each think there was room for both.
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
        // Null on the row means "use the shop default"; 0 is a real zero
        // (this customer may owe nothing at all), which is why the two are
        // distinguished rather than a null being read as zero.
        final int limit = ownLimit ?? defaultLimitMinor;
        // At the limit is allowed; past it is not, unless a manager approved
        // the sale — whose id arrives in [creditApprovedBy].
        if (balanceBefore + total.minorUnits > limit &&
            creditApprovedBy == null) {
          throw StateError(
              'That sale would take ${customerRow['name'] as String} past '
              'their credit limit');
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
            vatComponentForTaxClass(
              it.total,
              ratePercent: vatRatePercent,
              taxClass: taxClassByProduct[it.productId] ?? 'standard',
            ).minorUnits,
      );
      final int saleTaxableMinor = total.minorUnits - saleVatMinor;
      // Profit is based on VAT-exclusive revenue. The old calculation used
      // gross (VAT-inclusive) line totals, which overstated margin whenever
      // the shop collected VAT.
      final int saleCostMinor = items.fold<int>(
        0,
        (sum, item) => sum + item.unitCost.times(item.qty).minorUnits,
      );

      final saleId = await txn.insert('sales', {
        'staff_name': staffName,
        'staff_id': staffId,
        // The customer who takes an ON-ACCOUNT sale. Null for everything
        // else — the column is the link the aging, the statement and the
        // return-to-account all read.
        'customer_id': customerId,
        // Snapshot the buyer onto the immutable sale document. Customer rows
        // may later be edited or deactivated; retries and tax documents must
        // reproduce what was captured at checkout.
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

      // THE CHARGE: the ledger row that makes the promise, and the balance
      // cache updated beside it — the same transaction, same rule as every
      // other money move in this file. The row carries the approver when one
      // approved an over-limit sale, which is the AUDIT of that decision.
      if (paymentMethod == 'credit' && customerRow != null) {
        final int balanceBefore =
            (customerRow['balance_minor'] as num?)?.toInt() ?? 0;
        await txn.insert('credit_ledger', <String, Object?>{
          'uuid': _newUuid(),
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
          // The variant the line was sold as. Recorded as a snapshot, because
          // the owner renames "Dark" to "Black" next month and a reprint of
          // today's receipt must still say which size was sold.
          'variant_id': it.variantId,
          'variant_name': it.variantName,
          'pack_id': it.packId,
          'pack_qty': it.packQty,
          // The tax on this line, snapshotted at the moment of sale. The
          // product's own tax class can change tomorrow; today's receipt must
          // still carry today's figure.
          'tax_class': taxClassByProduct[it.productId] ?? 'standard',
          'vat_rate_bps': vatRatePercent * 100,
          'tax_rule_id': taxRuleId?.trim().isEmpty == true ? null : taxRuleId,
          'tax_rule_version': taxRuleVersion,
          'vat_minor': lineVatMinor,
          'taxable_minor': it.total.minorUnits - lineVatMinor,
        });
        final batchKey = it.variantId == null ? it.productId : -it.variantId!;
        final batchRows = batchesByProduct[batchKey];
        if (batchRows != null) {
          double remaining = it.qty * fraction;
          for (final batch in batchRows) {
            if (remaining <= _volumeTolerance) break;
            final available = (batch['qty_remaining'] as num).toDouble();
            if (available <= _volumeTolerance) continue;
            final taken = available < remaining ? available : remaining;
            final batchId = (batch['id'] as num).toInt();
            await txn.rawUpdate(
                "UPDATE stock_batches SET qty_remaining = qty_remaining - ?, "
                "status = CASE WHEN qty_remaining - ? <= ? THEN 'depleted' ELSE 'active' END "
                'WHERE id = ?',
                [taken, taken, _qtyEpsilon, batchId]);
            await txn.insert('sale_item_batches', {
              'sale_item_id': saleItemId,
              'batch_id': batchId,
              'qty': taken,
            });
            batch['qty_remaining'] = available - taken;
            remaining -= taken;
          }
          if (remaining > _volumeTolerance) {
            throw StateError('Unexpired stock changed while recording sale');
          }
        }
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
      for (final tender in tenderRows) {
        final tendered = tender.tendered ?? tender.amount;
        final tenderChange = tendered - tender.amount;
        await txn.insert('sale_payments', {
          'uuid': _newUuid(),
          'sale_id': saleId,
          'method': tender.method,
          // What was paid, without the change. The change is not payment.
          'amount_minor': tender.amount.minorUnits,
          'tendered_minor': tendered.minorUnits,
          'change_minor': tenderChange.minorUnits,
          'reference': tender.reference,
          'status': tender.status,
          'pending_payment_id': null,
          'created_at': now,
        });
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
          'document_type': 'sale',
        });
      }
      await _appendFinancialEvent(
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
        await _appendFinancialEvent(
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

    if (existingTransaction != null) return write(existingTransaction);
    return db!.transaction<int>((txn) => write(txn));
  }

  /// The count a variant is left with, read from the row the transaction has
  /// just written.
  Future<double> _variantBalanceAfter(
      DatabaseExecutor txn, int variantId) async {
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
  Future<double> _productBalanceAfter(
      DatabaseExecutor txn, int productId) async {
    final rows = await txn.query('products',
        columns: ['stock_qty'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1);
    if (rows.isEmpty) return 0;
    return (rows.first['stock_qty'] as num?)?.toDouble() ?? 0;
  }

  // ---------------- Customers and credit (v30) ----------------
  //
  // The ledger is the truth; `customers.balance_minor` is a cache. Every
  // method that touches one touches the other inside the same transaction, and
  // the ledger gains the new row FIRST — a balance cache that disagrees with
  // the account history it came from is worse than either figure alone.

  /// Lists customers.
  ///
  /// [search] matches name or phone, case-insensitively. [owsOnly] keeps only
  /// customers the shop owes nothing from... rather, only those owing
  /// something. Sorted by balance then name unless [sort] says otherwise
  /// (`name` | `balance` | `recent`).
  Future<List<Customer>> getCustomers({
    String search = '',
    bool activeOnly = true,
    bool owesOnly = false,
    String sort = 'balance',
  }) async {
    final where = <String>[
      if (activeOnly) 'active = 1',
      if (owesOnly) 'balance_minor > 0',
    ];
    final args = <Object?>[];
    final term = search.trim();
    if (term.isNotEmpty) {
      where.add('(name LIKE ? OR phone LIKE ?)');
      args
        ..add('%$term%')
        ..add('%$term%');
    }
    const orderBys = {
      'balance': 'balance_minor DESC, name COLLATE NOCASE ASC',
      'name': 'name COLLATE NOCASE ASC',
      'recent': 'id DESC',
    };
    final rows = await (await database).query('customers',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: orderBys[sort] ?? orderBys['balance']!);
    return rows.map(Customer.fromMap).toList();
  }

  /// One customer, or null.
  Future<Customer?> getCustomerById(int id) async {
    final rows = await (await database)
        .query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  /// The [Customer] a sale was sold to, or null. Used when the shop sizing a
  /// limit looks up what a sale already charged.
  Future<Customer?> customerOfSale(Map<String, dynamic> saleRow) async {
    final id = (saleRow['customer_id'] as num?)?.toInt();
    if (id == null) return null;
    return getCustomerById(id);
  }

  /// Creates or updates a customer.
  ///
  /// Two uniqueness rules, both among ACTIVE customers (a deactivated
  /// customer's name and phone are reusable):
  ///  * the name, compared case-insensitively — "Mary Wanjiku" and
  ///    "mary wanjiku" are the one person;
  ///  * the phone, when present, in canonical +254 form.
  ///
  /// Returns the id. Throws [StateError] with the reason when either rule is
  /// broken, which the caller renders in the shop's language.
  Future<int> upsertCustomer(Customer customer) async {
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
    final db = await database;
    return db.transaction<int>((txn) async {
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
          : _canonicalPhone(customer.phone!);
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
    });
  }

  /// Deactivates a customer.
  ///
  /// A customer the shop still owes money for — a non-zero balance — cannot
  /// be deactivated: their debt has to be settled or written off first,
  /// because an inactive customer cannot take a payment through the normal
  /// flows and the debt would become unaccountable.
  Future<void> deactivateCustomer(int id) async {
    final customer = await getCustomerById(id);
    if (customer == null) return;
    if (customer.balanceMinor != 0) {
      throw StateError(
          'Settle or write off the balance before removing a customer');
    }
    await (await database)
        .update('customers', {'active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  /// The canonical form of a phone as typed, or null.
  String? _canonicalPhone(String raw) {
    if (raw.startsWith('+254')) return normaliseKenyanPhone(raw);
    final fromLocal = normaliseKenyanPhone(raw);
    return fromLocal;
  }

  /// What a customer's payments settled: (payment, settled charge, amount).
  ///
  /// Read through the payments' entries so the DETAIL SHEET can show which
  /// old invoice a payment was laid against — the FIFO order's receipt.
  Future<List<CreditAllocation>> getCreditAllocations(int customerId) async {
    final rows = await (await database).rawQuery('''
      SELECT a.payment_entry_id, a.charge_entry_id, a.amount_minor
      FROM credit_allocations a
      JOIN credit_ledger l ON l.id = a.payment_entry_id
      WHERE l.customer_id = ?
      ORDER BY a.id ASC
    ''', [customerId]);
    return [
      for (final row in rows)
        CreditAllocation(
          paymentEntryId: row['payment_entry_id'] as int,
          chargeEntryId: row['charge_entry_id'] as int,
          amountMinor: (row['amount_minor'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  /// The credit entries of one customer, newest first.
  Future<List<CreditLedgerEntry>> getCreditEntries(int customerId) async {
    final rows = await (await database).query('credit_ledger',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'created_at DESC, id DESC');
    return rows.map(CreditLedgerEntry.fromMap).toList();
  }

  /// Full customer/ledger batch for the online mirror. The local database
  /// remains the source of truth while offline; the server upserts these rows
  /// by UUID when a connection is available.
  Future<List<Customer>> getAllCustomersForSync() async {
    final rows = await (await database).query('customers', orderBy: 'id ASC');
    return rows.map(Customer.fromMap).toList();
  }

  Future<List<CreditLedgerEntry>> getAllCreditEntriesForSync() async {
    final rows = await (await database)
        .query('credit_ledger', orderBy: 'created_at ASC, id ASC');
    return rows.map(CreditLedgerEntry.fromMap).toList();
  }

  /// Merges a server credit snapshot after local uploads have completed.
  /// Customer UUIDs, not device row ids, are the cross-device identity; ledger
  /// UUIDs are inserted with ignore semantics so the append-only history is
  /// never edited or duplicated.
  Future<void> mergeRemoteCreditSnapshot({
    required List<Map<String, dynamic>> customers,
    required List<Map<String, dynamic>> entries,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final customer in customers) {
        final uuid = customer['localUuid'] as String?;
        if (uuid == null || uuid.isEmpty) continue;
        final existing = await txn.query('customers',
            columns: ['id'], where: 'uuid = ?', whereArgs: [uuid], limit: 1);
        final values = <String, Object?>{
          'uuid': uuid,
          'name': customer['name'] as String? ?? 'Customer',
          'phone': customer['phone'],
          'tin': customer['tin'],
          'notes': customer['notes'],
          'credit_limit_minor': customer['creditLimitMinor'],
          'balance_minor': (customer['balanceMinor'] as num?)?.toInt() ?? 0,
          'active': customer['active'] == true ? 1 : 0,
          'created_at': customer['createdAt'] as String? ??
              DateTime.now().toIso8601String(),
        };
        if (existing.isEmpty) {
          await txn.insert('customers', values);
        } else {
          await txn.update('customers', values,
              where: 'id = ?', whereArgs: [existing.first['id']]);
        }
      }
      for (final entry in entries) {
        final uuid = entry['localUuid'] as String?;
        final customerUuid = entry['customerUuid'] as String?;
        if (uuid == null || uuid.isEmpty || customerUuid == null) continue;
        final customer = await txn.query('customers',
            columns: ['id'],
            where: 'uuid = ?',
            whereArgs: [customerUuid],
            limit: 1);
        if (customer.isEmpty) continue;
        await txn.insert(
            'credit_ledger',
            {
              'uuid': uuid,
              'customer_id': customer.first['id'],
              'entry_type': entry['entryType'] as String? ?? 'charge',
              'amount_minor': (entry['amountMinor'] as num?)?.toInt() ?? 0,
              'sale_id': entry['saleLocalId'],
              'return_id': entry['returnLocalId'],
              'payment_method': entry['paymentMethod'],
              'reference': entry['reference'],
              'staff_name': entry['staffName'] as String? ?? '',
              'note': entry['note'],
              'created_at': entry['createdAt'] as String? ??
                  DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  /// The open (not fully allocated) charges of a set of customers, oldest
  /// charge first per customer.
  Future<
      List<
          ({
            int chargeEntryId,
            int customerId,
            int outstandingMinor,
            String createdAt
          })>> openCreditCharges({required int? customerId}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT l.id AS entry_id, l.customer_id, l.amount_minor AS charged,
             COALESCE((SELECT SUM(a.amount_minor) FROM credit_allocations a
                       WHERE a.charge_entry_id = l.id), 0) AS allocated,
             l.created_at
      FROM credit_ledger l
      WHERE l.entry_type = 'charge'
        AND (${customerId == null ? '1' : 'l.customer_id = ?'})
      ORDER BY l.created_at ASC, l.id ASC
    ''', [if (customerId != null) customerId]);
    return [
      for (final row in rows)
        if (((row['charged'] as num).toInt() -
                (row['allocated'] as num).toInt()) >
            0)
          (
            chargeEntryId: row['entry_id'] as int,
            customerId: row['customer_id'] as int,
            outstandingMinor: (row['charged'] as num).toInt() -
                (row['allocated'] as num).toInt(),
            createdAt: row['created_at'] as String,
          ),
    ];
  }

  /// Repays some or all of a customer's debt.
  ///
  /// The payment is a NEGATIVE ledger entry (money going down as owed), is
  /// allocated against the open charges oldest first, and — when taken in
  /// cash — belongs to the shift that is open NOW, because the money sits in
  /// THAT drawer. A cash repayment without an open shift is refused, exactly
  /// like a cash refund.
  Future<int> recordCreditRepayment({
    required int customerId,
    required Money amount,

    /// `cash` or `mpesa`.
    required String method,
    String? reference,
    String? note,
    int? staffId,
    required String staffName,
  }) async {
    if (amount.minorUnits <= 0) {
      throw StateError('A repayment must be more than zero');
    }
    if (method != 'cash' && method != 'mpesa') {
      throw StateError('A repayment is cash or M-Pesa');
    }
    final db = await database;
    return db.transaction<int>((txn) async {
      final rows = await txn.query('customers',
          where: 'id = ?', whereArgs: [customerId], limit: 1);
      if (rows.isEmpty) throw StateError('Customer not found');
      final balanceBefore = (rows.first['balance_minor'] as num?)?.toInt() ?? 0;

      int? shiftId;
      if (method == 'cash') {
        final shift = await txn.query('shifts',
            where: 'status = ?',
            whereArgs: ['open'],
            orderBy: 'start_time DESC',
            limit: 1);
        if (shift.isEmpty) {
          throw StateError(
              'Open a shift before taking cash in, so the drawer can be counted');
        }
        shiftId = shift.first['id'] as int;
      }

      final now = DateTime.now().toIso8601String();
      final eventAtUtc = DateTime.now().toUtc().toIso8601String();
      final entryId = await txn.insert('credit_ledger', {
        'uuid': _newUuid(),
        'customer_id': customerId,
        'entry_type': 'payment',
        'amount_minor': -amount.minorUnits,
        'payment_method': method,
        'reference': reference,
        'shift_id': shiftId,
        'staff_id': staffId,
        'staff_name': staffName,
        'note': note,
        'created_at': now,
      });

      // Oldest debts first — THIS customer's only, which the query names or
      // two customers' repayments would settle each other's invoices.
      // Every open charge is read with what is still outstanding on it, and
      // the payment is spread across them in order. What is allocated is
      // bounded by the payment itself (the loop's [remaining]), so overpayment
      // simply leaves charges open and the balance goes negative —
      // "credit with us".
      var remaining = amount.minorUnits;
      final chargeRows = await txn.rawQuery('''
        SELECT l.id,
               l.amount_minor - COALESCE((SELECT SUM(a.amount_minor)
                  FROM credit_allocations a WHERE a.charge_entry_id = l.id), 0)
                 AS outstanding
        FROM credit_ledger l
        WHERE l.entry_type = 'charge'
          AND l.customer_id = ?
          AND l.amount_minor - COALESCE((SELECT SUM(a.amount_minor)
                  FROM credit_allocations a WHERE a.charge_entry_id = l.id), 0) > 0
        ORDER BY l.created_at ASC, l.id ASC
      ''', [customerId]);
      for (final charge in chargeRows) {
        if (remaining <= 0) break;
        final outstanding = (charge['outstanding'] as num).toInt();
        final applied = outstanding < remaining ? outstanding : remaining;
        if (applied <= 0) continue;
        await txn.insert('credit_allocations', {
          'payment_entry_id': entryId,
          'charge_entry_id': charge['id'] as int,
          'amount_minor': applied,
        });
        remaining -= applied;
      }

      // Cached balance, updated in the same transaction as the ledger row.
      // The WHOLE payment reduces the debt, whether or not it fully settles a
      // specific charge; the leftover sits as credit with us.
      await txn.rawUpdate(
        'UPDATE customers SET balance_minor = ? WHERE id = ?',
        [balanceBefore - amount.minorUnits, customerId],
      );
      await _appendFinancialEvent(
        txn: txn,
        eventType: 'credit_repayment',
        sourceType: 'credit_ledger',
        sourceId: entryId,
        occurredAtUtc: eventAtUtc,
        cashInMinor: amount.minorUnits,
        receivableDeltaMinor: -amount.minorUnits,
        metadata: <String, Object?>{
          'customer_id': customerId,
          'method': method,
          'has_reference': reference != null && reference.trim().isNotEmpty,
        },
      );
      return entryId;
    });
  }

  /// A signed correction or a write-off, taken against a customer's balance.
  ///
  /// [type] is `adjustment` (a signed correction) or `writeoff` (debt given
  /// up on; always negative). A write-off may never exceed what the customer
  /// owes, and both need the manager or owner who approved them — their id is
  /// [approvedBy] and goes on the ledger row, which is the audit record.
  Future<int> recordCreditAdjustment({
    required int customerId,
    required int amountMinor,
    required String type,
    required String staffName,
    int? staffId,
    required int approvedBy,
    String? note,
  }) async {
    if (type != 'adjustment' && type != 'writeoff') {
      throw StateError('A correction is an adjustment or a write-off');
    }
    if (amountMinor == 0) {
      throw StateError('Nothing to correct');
    }
    if (type == 'writeoff' && amountMinor > 0) {
      // Sign-normalised at the boundary: a write-off always reduces.
      amountMinor = -amountMinor.abs();
    }
    final db = await database;
    return db.transaction<int>((txn) async {
      final rows = await txn.query('customers',
          where: 'id = ?', whereArgs: [customerId], limit: 1);
      if (rows.isEmpty) throw StateError('Customer not found');
      final balanceBefore = (rows.first['balance_minor'] as num?)?.toInt() ?? 0;
      if (amountMinor < 0 &&
          balanceBefore + amountMinor < 0 &&
          type == 'writeoff') {
        throw StateError('That is more than the customer currently owes');
      }
      final now = DateTime.now().toIso8601String();
      final entryId = await txn.insert('credit_ledger', {
        'uuid': _newUuid(),
        'customer_id': customerId,
        'entry_type': type,
        'amount_minor': amountMinor,
        'staff_id': staffId,
        'staff_name': staffName,
        'approved_by': approvedBy,
        'note': note,
        'created_at': now,
      });
      int? badDebtExpenseId;
      if (type == 'writeoff') {
        final badDebtCategory = await txn.query(
          'expense_categories',
          columns: ['id'],
          where: 'name = ? AND active = 1',
          whereArgs: ['Bad debts'],
          limit: 1,
        );
        if (badDebtCategory.isEmpty) {
          throw StateError('Bad debts expense category not found');
        }
        badDebtExpenseId = await txn.insert('expenses', {
          'uuid': _newUuid(),
          'shift_id': null,
          'category_id': badDebtCategory.first['id'] as int,
          'amount_minor': amountMinor.abs(),
          'paid_from': 'other',
          'note': note,
          'photo_path': null,
          'staff_id': staffId,
          'staff_name': staffName,
          'created_at': now,
        });
      }
      await txn.rawUpdate('UPDATE customers SET balance_minor = ? WHERE id = ?',
          [balanceBefore + amountMinor, customerId]);
      await _appendFinancialEvent(
        txn: txn,
        eventType: type == 'writeoff' ? 'credit_writeoff' : 'credit_adjustment',
        sourceType: 'credit_ledger',
        sourceId: entryId,
        occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
        receivableDeltaMinor: amountMinor,
        metadata: <String, Object?>{
          'customer_id': customerId,
          'approved_by': approvedBy,
          'adjustment_type': type,
        },
      );
      if (badDebtExpenseId != null) {
        await _appendFinancialEvent(
          txn: txn,
          eventType: 'bad_debt_expense',
          sourceType: 'expense',
          sourceId: badDebtExpenseId,
          occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
          operatingExpenseMinor: amountMinor.abs(),
          metadata: <String, Object?>{
            'credit_ledger_id': entryId,
            'customer_id': customerId,
          },
        );
      }
      return entryId;
    });
  }

  /// How the till sees credit: the total outstanding and who owes it most.
  Future<({int totalOwedMinor, int customerCount})> creditSummary() async {
    final rows = await (await database).rawQuery(
      'SELECT COALESCE(SUM(balance_minor), 0) AS total, '
      'COUNT(*) AS n FROM customers WHERE active = 1 AND balance_minor > 0',
    );
    return (
      totalOwedMinor: (rows.first['total'] as num?)?.toInt() ?? 0,
      customerCount: (rows.first['n'] as num?)?.toInt() ?? 0,
    );
  }

  /// Ages the debts the shop is owed, by the OLDEST unpaid charge per
  /// customer. Buckets: 0-7, 8-30, 31-60 and over 60 days.
  /// Ages the debts the shop is owed, by the OLDEST unpaid charge per
  /// customer. Buckets: 0-7, 8-30, 31-60 and over 60 days.
  ///
  /// The amounts summed per bucket are each charge's OUTSTANDING remainder
  /// (charged minus what has been allocated against it), so the bucket sums
  /// add up to the shop's total owed, and a part-paid debt lands in the bucket
  /// its oldest unpaid charge falls in — which is what "this is 40 days old"
  /// means when part of it was settled on Tuesday.
  Future<
      Map<DebtAgeBucket,
          ({int amountMinor, int customers, int overdueCount})>> creditAging(
      {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final openCharges = await openCreditCharges(customerId: null);

    final outstandingByCustomer = <int, int>{};
    final oldestOpenPerCustomer = <int, String>{};
    for (final charge in openCharges) {
      outstandingByCustomer[charge.customerId] =
          (outstandingByCustomer[charge.customerId] ?? 0) +
              charge.outstandingMinor;
      final existing = oldestOpenPerCustomer[charge.customerId];
      if (existing == null || charge.createdAt.compareTo(existing) < 0) {
        oldestOpenPerCustomer[charge.customerId] = charge.createdAt;
      }
    }

    final totalByBucket = <DebtAgeBucket, int>{
      for (final bucket in DebtAgeBucket.values) bucket: 0,
    };
    final customersByBucket = <DebtAgeBucket, int>{
      for (final bucket in DebtAgeBucket.values) bucket: 0,
    };
    for (final customerId in outstandingByCustomer.keys) {
      final createdAt =
          DateTime.tryParse(oldestOpenPerCustomer[customerId] ?? '') ?? at;
      final bucket = DebtAgeBucket.forAge(at.difference(createdAt).inDays);
      totalByBucket[bucket] =
          (totalByBucket[bucket] ?? 0) + outstandingByCustomer[customerId]!;
      customersByBucket[bucket] = (customersByBucket[bucket] ?? 0) + 1;
    }

    return {
      for (final bucket in DebtAgeBucket.values)
        bucket: (
          amountMinor: totalByBucket[bucket] ?? 0,
          customers: customersByBucket[bucket] ?? 0,
          overdueCount: customersByBucket[DebtAgeBucket.over60Days] ?? 0,
        ),
    };
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
              documentType: row['document_type'] as String? ?? 'sale',
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

  /// Local issuance status counts for the Sync Center. Issued rows remain
  /// visible as evidence of completed filing; they are never deletable from
  /// this operational surface.
  Future<Map<String, int>> etimsStatusCounts() async {
    final rows = await (await database).rawQuery(
      'SELECT etims_status, COUNT(*) AS c FROM sales GROUP BY etims_status',
    );
    return <String, int>{
      for (final row in rows)
        (row['etims_status'] as String? ?? EtimsStatus.notRequired):
            (row['c'] as num).toInt(),
    };
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
      documentType: row['document_type'] as String? ?? 'sale',
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
      buyerName: sale.buyerName,
      buyerTin: sale.buyerTin,
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
            buyerName: s.buyerName,
            buyerTin: s.buyerTin,
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
    DatabaseExecutor? existingTransaction,
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

    final db = existingTransaction == null ? await database : null;
    Future<int> write(DatabaseExecutor txn) async {
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
      int restockedCostMinor = 0;
      int writtenOffCostMinor = 0;
      int restockedMilliunits = 0;
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
        // SaleItem.total already includes the recorded line discount, so a
        // partial return refunds the discounted amount rather than today's
        // list price.
        final int lineTotal = sold.total.minorUnits;
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
        final int returnCostMinor = _roundHalfUp(
          sold.unitCost.minorUnits * draft.qty,
        );
        if (draft.restock) {
          restockedCostMinor += returnCostMinor;
          restockedMilliunits += (units * 1000).round();
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
          // Put a restocked return back into the exact batches it came from.
          // Pro-rating keeps a partial return auditable and avoids turning an
          // older batch into a newer one merely because the product balance is
          // aggregated at the catalogue level.
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

      // A credit-account sale REFUNDS to the account by default (spec
      // 7.5.4): the reversal is a return_credit entry against the customer's
      // ledger, in the same transaction as the return — never a drawer
      // action, never an edit.
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
          'uuid': _newUuid(),
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

      await _appendFinancialEvent(
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

    if (existingTransaction != null) return write(existingTransaction);
    return db!.transaction<int>((txn) => write(txn));
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
      final allocationRows = await db.query(
        'sale_return_refunds',
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
            refundAllocations:
                allocationRows.map(ReturnRefundAllocation.fromMap).toList(),
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
    String? supplierPin,
    String? etimsInvoiceRef,
    int? inputVatMinor,
    String taxEvidenceStatus = 'needs_review',
    String? note,
    required String staffName,
    int? staffId,
    DateTime? receivedAt,

    /// How the delivery prices what it brings: `weighted_average` (the shop
    /// setting, and the default) blends the incoming cost with what is still
    /// on the shelf; `last_cost` replaces the product's cost outright.
    ///
    /// Read once by the caller from the shop setting and passed in, so the
    /// mode in force for this posting is the one the owner saw on the screen.
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
    final db = await database;
    return db.transaction<int>((txn) async {
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
          if (received + line.qty > ordered + _qtyEpsilon) {
            throw StateError('Received quantity exceeds the purchase order');
          }
        }
        final int oldCost = (product.first['cost_price'] as num?)?.toInt() ?? 0;
        final int newCost;
        if (costingMode == 'weighted_average') {
          // Half-up against exact integers, never a float: the ONE division
          // primitive every average in this app goes through.
          newCost = _weightedAverageCost(
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
          // What one unit cost HERE — the supplier's price. A blended figure
          // belongs in new_cost_minor; storing it in BOTH columns would make
          // the prefill of the next delivery show a book average as if the
          // supplier had asked for it.
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
            'uuid': _newUuid(),
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

      await _appendFinancialEvent(
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
    });
  }

  /// Posts a delivery entered in packs while keeping the stock ledger in base
  /// units. The pack cost is the cost of one pack; the receipt line stores the
  /// derived unit cost and quantity so profit and future counts stay coherent.
  Future<int> postStockReceiptByPack({
    required int packId,
    required double packQty,
    required String staffName,
    int? staffId,
    int? supplierId,
    String? supplierRef,
    String? note,
    DateTime? receivedAt,
  }) async {
    if (!packQty.isFinite || packQty <= 0) {
      throw ArgumentError.value(packQty, 'packQty');
    }
    final rows = await (await database).query(
      'product_packs',
      where: 'id = ? AND active = 1',
      whereArgs: [packId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Pack not found');
    final pack = ProductPack.fromMap(rows.first);
    final productRows = await (await database).query(
      'products',
      where: 'id = ? AND active = 1',
      whereArgs: [pack.productId],
      limit: 1,
    );
    if (productRows.isEmpty) throw StateError('Pack product not found');
    final product = Product.fromMap(productRows.first);
    return postStockReceipt(
      lines: [
        StockReceiptLine(
          productId: product.id!,
          productName: product.name,
          qty: packQty * pack.unitsPerPack,
          variantId: pack.variantId,
          unitCost: Money.fromMinor(
              (pack.unitCost.minorUnits / pack.unitsPerPack).round()),
        ),
      ],
      supplierId: supplierId,
      supplierRef: supplierRef,
      note: note == null ? 'Received ${pack.name}' : '$note (${pack.name})',
      staffName: staffName,
      staffId: staffId,
      receivedAt: receivedAt,
    );
  }

  /// The weighted-average cost [incomingQty] units of a delivery leave a
  /// product standing at.
  ///
  /// `(on-hand value + incoming value) / (on-hand + incoming)`, with on-hand
  /// BELOW zero read as zero — a negative shelf is a stocktake problem, not a
  /// reason for the cost to dive. Result is quantised half-up by the one
  /// division primitive, so a two-delivery chain cannot drift a cent from
  /// doing the same sums once.
  ///
  /// Returns the incoming cost unchanged when nothing is on hand: first stock
  /// IS the cost, by either mode.
  static int _weightedAverageCost({
    required int onHandMinor,
    required double onHandQty,
    required double incomingQty,
    required int incomingMinor,
  }) {
    if (incomingQty <= 0) return onHandMinor;
    final double shelf = onHandQty > 0 ? onHandQty : 0;
    if (shelf <= 0) return incomingMinor;
    final double total = shelf + incomingQty;
    final int valueMinor =
        (shelf * onHandMinor).round() + (incomingQty * incomingMinor).round();
    return divideMoneyHalfUp(valueMinor, total.round());
  }

  /// Voids a posted delivery.
  ///
  /// Only while the stock it brought is still on hand: each line's quantity
  /// must still be in the shop, because taking stock back that has already
  /// been sold would need a stocktake, not a void — the shortfall is named in
  /// the error, and the receipt stays posted. The void writes one
  /// receipt_void movement per line IN THE SAME TRANSACTION (a crash cannot
  /// leave half a void), restores the previous cost from history where no
  /// later receipt has already moved cost past this one, and marks the
  /// receipt `voided` — it stays visible in the history, in that state.
  ///
  /// Returns the number of lines voided.
  Future<int> voidStockReceipt({
    required int receiptId,
    required String staffName,
    int? staffId,
  }) async {
    final db = await database;
    return db.transaction<int>((txn) async {
      final receipts = await txn.query('stock_receipts',
          where: 'id = ?', whereArgs: [receiptId], limit: 1);
      if (receipts.isEmpty) {
        throw StateError('That delivery is not in the history');
      }
      if ((receipts.first['status'] as String?) == 'voided') {
        throw StateError('That delivery is already voided');
      }
      final String receivedAt = receipts.first['received_at'] as String? ??
          DateTime.now().toIso8601String();
      final lines = await txn.query('stock_receipt_items',
          where: 'receipt_id = ?', whereArgs: [receiptId], orderBy: 'id ASC');
      if (lines.isEmpty) {
        throw StateError('That delivery has no lines to reverse');
      }

      // The whole void is judged BEFORE any row moves: one short line voids
      // nothing, rather than reversing half a delivery.
      for (final line in lines) {
        final double taken = (line['qty'] as num).toDouble();
        final int productId = line['product_id'] as int;
        final current = await txn.query('products',
            columns: <String>['stock_qty', 'name'],
            where: 'id = ?',
            whereArgs: [productId],
            limit: 1);
        final double onHand =
            (current.first['stock_qty'] as num?)?.toDouble() ?? 0;
        if (onHand + _volumeTolerance < taken) {
          throw StateError('${current.first['name'] as String} is short: only '
              '${onHand.toStringAsFixed(0)} left of the ${taken.toStringAsFixed(0)} '
              'this delivery brought');
        }
      }

      final String now = DateTime.now().toIso8601String();
      final int totalCost = lines.fold<int>(
        0,
        (sum, line) => sum + ((line['line_cost_minor'] as num?)?.toInt() ?? 0),
      );
      final int inventoryMilliunits = lines.fold<int>(
        0,
        (sum, line) => sum + (((line['qty'] as num).toDouble()) * 1000).round(),
      );
      for (final line in lines) {
        final double taken = (line['qty'] as num).toDouble();
        final int productId = line['product_id'] as int;
        final variantId = (line['variant_id'] as num?)?.toInt();
        final int unitCost = (line['unit_cost_minor'] as num?)?.toInt() ?? 0;
        final double balance = variantId == null
            ? await _productBalanceAfter(txn, productId)
            : await _variantBalanceAfter(txn, variantId);
        await _writeStockMovement(
          txn,
          productId: productId,
          variantId: variantId,
          type: StockMovementType.receiptVoid,
          qtyDelta: -taken,
          unitCostMinor: unitCost,
          referenceType: 'stock_receipt',
          referenceId: receiptId,
          staffId: staffId,
          staffName: staffName,
          note: 'Voided delivery',
          balanceAfter: balance,
          createdAt: now,
        );
        await txn.rawUpdate(
          'UPDATE products SET stock_qty = MAX(0, stock_qty - ?), '
          'updated_at = ? WHERE id = ?',
          <Object?>[taken, now, productId],
        );
        if (variantId != null) {
          await txn.rawUpdate(
            'UPDATE product_variants SET stock_qty = MAX(0, stock_qty - ?) '
            'WHERE id = ?',
            <Object?>[taken, variantId],
          );
        }

        // Cost: roll back ONLY when this delivery is still the newest thing
        // that touched the cost. A later receipt's figures own the cost now;
        // reversing an old average against a live one would corrupt it.
        final later = await txn.rawQuery(
          'SELECT COUNT(*) AS n FROM product_cost_history '
          'WHERE product_id = ? AND receipt_id != ? AND effective_at > ?',
          <Object?>[productId, receiptId, receivedAt],
        );
        if ((later.first['n'] as num?)?.toInt() == 0) {
          final oldCost = (line['old_cost_minor'] as num?)?.toInt() ?? 0;
          await txn.rawUpdate(
            'UPDATE products SET cost_price = ? WHERE id = ?',
            <Object?>[oldCost, productId],
          );
          await txn.insert('product_cost_history', {
            'product_id': productId,
            'variant_id': variantId,
            'effective_at': now,
            'old_cost_minor': unitCost,
            'new_cost_minor': oldCost,
            'reason': 'void',
            'receipt_id': receiptId,
          });
        }
      }

      await txn.update('stock_receipts', {'status': 'voided'},
          where: 'id = ?', whereArgs: [receiptId]);
      await _appendFinancialEvent(
        txn: txn,
        eventType: 'purchase_void',
        sourceType: 'stock_receipt',
        sourceId: receiptId,
        occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
        payableDeltaMinor: -totalCost,
        inventoryDeltaMilliunits: -inventoryMilliunits,
        metadata: <String, Object?>{'line_count': lines.length},
      );
      return lines.length;
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
            supplierPin: r.supplierPin,
            etimsInvoiceRef: r.etimsInvoiceRef,
            inputVat: r.inputVat,
            taxEvidenceStatus: r.taxEvidenceStatus,
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
    // The last PAID figure — what one unit went for on the newest delivery —
    // not the book cost: under weighted average the modelled cost is a blend,
    // and the number the owner is about to type again is the price the
    // supplier actually asked.
    final rows = await (await database).rawQuery(
      'SELECT unit_cost_minor FROM stock_receipt_items '
      'WHERE product_id = ? AND unit_cost_minor > 0 '
      'ORDER BY id DESC LIMIT 1',
      [productId],
    );
    if (rows.isNotEmpty) {
      return Money.fromMinor(
          (rows.first['unit_cost_minor'] as num?)?.toInt() ?? 0);
    }
    // Nothing bought yet: the cheapest thing it has ever cost.
    final history = await (await database).rawQuery(
      'SELECT new_cost_minor FROM product_cost_history '
      'WHERE product_id = ? ORDER BY effective_at DESC, id DESC LIMIT 1',
      [productId],
    );
    if (history.isEmpty) return null;
    return Money.fromMinor(
        (history.first['new_cost_minor'] as num?)?.toInt() ?? 0);
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
    int? leadTimeDays,
    String? paymentTerms,
    String? orderChannel,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('A supplier needs a name');
    }
    // Stored in the canonical +254… form or not at all: a number typed one
    // way today and another way next week is ONE supplier's number only if
    // the app treats the six spellings as one. Anything that is not a
    // Kenyan number is refused rather than stored broken — an unreadable
    // number would be a restock message that never reached anyone.
    String? canonical;
    final typed = phone?.trim();
    if (typed != null && typed.isNotEmpty) {
      canonical = normaliseKenyanPhone(typed);
      if (canonical == null) {
        throw ArgumentError.value(phone, 'phone',
            'not a Kenyan number: 07xx, 01xx, +254 or 254 form');
      }
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
      'phone': canonical,
      'contact_person': contactPerson,
      'notes': notes,
      'lead_time_days': leadTimeDays,
      'payment_terms': paymentTerms,
      'order_channel': orderChannel,
      'active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> linkProductSupplier({
    required String uuid,
    required int productId,
    required int supplierId,
    int? packId,
    String? supplierSku,
    bool preferred = false,
  }) async {
    await (await database).insert(
        'product_suppliers',
        {
          'uuid': uuid,
          'product_id': productId,
          'supplier_id': supplierId,
          'pack_id': packId,
          'supplier_sku': supplierSku,
          'preferred': preferred ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getProductSuppliers(int productId) async =>
      (await database).rawQuery('''
        SELECT ps.*, s.name AS supplier_name, s.phone AS supplier_phone
        FROM product_suppliers ps JOIN suppliers s ON s.id = ps.supplier_id
        WHERE ps.product_id = ? ORDER BY ps.preferred DESC, s.name
      ''', [productId]);

  Future<int> createPurchaseOrder({
    required String uuid,
    required int supplierId,
    required String staffName,
    required List<Map<String, Object?>> lines,
    int? staffId,
    String? note,
    DateTime? expectedAt,
  }) async {
    if (lines.isEmpty) throw StateError('A purchase order needs lines');
    final db = await database;
    return db.transaction<int>((txn) async {
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('purchase_orders', {
        'uuid': uuid,
        'order_number': 'PO-PENDING-$uuid',
        'supplier_id': supplierId,
        'status': 'draft',
        'expected_at': expectedAt?.toIso8601String(),
        'note': note,
        'created_at': now,
        'staff_id': staffId,
        'staff_name': staffName,
      });
      final number =
          'PO-${DateTime.now().year}-${id.toString().padLeft(6, '0')}';
      await txn.update('purchase_orders', {'order_number': number},
          where: 'id = ?', whereArgs: [id]);
      for (final line in lines) {
        final qty = (line['qty'] as num?)?.toDouble() ?? 0;
        if (qty <= 0) throw StateError('Purchase quantity must be positive');
        await txn.insert('purchase_order_lines', {
          'uuid': _newUuid(),
          'purchase_order_id': id,
          'product_id': line['product_id'],
          'product_name': line['product_name'],
          'qty': qty,
          'unit_cost_minor': line['unit_cost_minor'] ?? 0,
        });
      }
      return id;
    });
  }

  Future<List<Map<String, dynamic>>> getPurchaseOrders({
    int? supplierId,
    String? status,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (supplierId != null) {
      where.add('supplier_id = ?');
      args.add(supplierId);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    return (await database).query(
      'purchase_orders',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getPurchaseOrderLines(int orderId) async =>
      (await database).query(
        'purchase_order_lines',
        where: 'purchase_order_id = ?',
        whereArgs: [orderId],
        orderBy: 'id ASC',
      );

  /// Reordering is a draft workflow, but drafts still belong to the shop's
  /// shared operational history. Return bounded, idempotent records for the
  /// verified sync cycle; automatic ordering is never triggered here.
  Future<List<Map<String, dynamic>>> getUnsyncedReorderRecords(
      {int limit = 100}) async {
    final db = await database;
    final records = <Map<String, dynamic>>[];
    for (final row in await db.query('suppliers',
        where: 'synced_to_backend = 0', orderBy: 'id ASC', limit: limit)) {
      records.add(<String, dynamic>{
        'kind': 'supplier',
        'localId': row['id'],
        'createdAt': row['created_at'],
        'payload': Map<String, dynamic>.from(row),
      });
    }
    for (final row in await db.rawQuery('''
      SELECT ps.*, s.name AS supplier_name
      FROM product_suppliers ps JOIN suppliers s ON s.id = ps.supplier_id
      WHERE ps.synced_to_backend = 0
      ORDER BY ps.id ASC LIMIT ?
    ''', [limit])) {
      records.add(<String, dynamic>{
        'kind': 'product_supplier',
        'localId': row['id'],
        'createdAt': DateTime.now().toIso8601String(),
        'payload': Map<String, dynamic>.from(row),
      });
    }
    for (final row in await db.query('purchase_orders',
        where: 'synced_to_backend = 0', orderBy: 'id ASC', limit: limit)) {
      final payload = Map<String, dynamic>.from(row);
      final supplier = await db.rawQuery(
          'SELECT name FROM suppliers WHERE id = ?', [row['supplier_id']]);
      if (supplier.isNotEmpty) {
        payload['supplier_name'] = supplier.first['name'];
      }
      payload['lines'] = await getPurchaseOrderLines(row['id'] as int);
      records.add(<String, dynamic>{
        'kind': 'purchase_order',
        'localId': row['id'],
        'createdAt': row['created_at'],
        'payload': payload,
      });
    }
    return records.take(limit).toList();
  }

  Future<void> markReorderRecordsSynced(
      List<Map<String, dynamic>> records) async {
    if (records.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final record in records) {
        final id = record['localId'];
        final kind = record['kind'];
        final table = switch (kind) {
          'supplier' => 'suppliers',
          'product_supplier' => 'product_suppliers',
          'purchase_order' => 'purchase_orders',
          _ => null,
        };
        if (table != null && id is int) {
          await txn.update(table, {'synced_to_backend': 1},
              where: 'id = ?', whereArgs: [id]);
        }
      }
    });
  }

  /// Applies a reorder record received from another verified till. Supplier
  /// names are the portable identity; product links use the server product
  /// UUID carried by the sender, never another phone's integer id.
  Future<void> mergeRemoteReorderRecord(Map<String, dynamic> record) async {
    final kind = record['entityKind'] as String?;
    final raw = record['payload'];
    if (kind == null || raw is! Map) return;
    final payload = Map<String, dynamic>.from(raw);
    final db = await database;
    if (kind == 'supplier') {
      final name = payload['name']?.toString().trim() ?? '';
      if (name.isEmpty) return;
      final existing = await db.query('suppliers',
          where: 'LOWER(name) = ?', whereArgs: [name.toLowerCase()], limit: 1);
      if (existing.isEmpty) {
        await db.insert('suppliers', {
          'name': name,
          'phone': payload['phone'],
          'contact_person': payload['contact_person'],
          'notes': payload['notes'],
          'lead_time_days': payload['lead_time_days'],
          'payment_terms': payload['payment_terms'],
          'order_channel': payload['order_channel'],
          'active': payload['active'] ?? 1,
          'synced_to_backend': 1,
          'created_at':
              payload['created_at'] ?? DateTime.now().toIso8601String(),
        });
      }
      return;
    }
    if (kind == 'product_supplier') {
      final remoteProductId = payload['product_remote_id']?.toString();
      final supplierName = payload['supplier_name']?.toString().trim() ?? '';
      if (remoteProductId == null || supplierName.isEmpty) return;
      final products = await db.query('products',
          where: 'remote_id = ?', whereArgs: [remoteProductId], limit: 1);
      final suppliers = await db.query('suppliers',
          where: 'LOWER(name) = ?',
          whereArgs: [supplierName.toLowerCase()],
          limit: 1);
      if (products.isEmpty || suppliers.isEmpty) return;
      await db.insert(
          'product_suppliers',
          {
            'uuid': 'remote-${record['remoteId']}',
            'product_id': products.single['id'],
            'supplier_id': suppliers.single['id'],
            'supplier_sku': payload['supplier_sku'],
            'pack_id': null,
            'preferred': payload['preferred'] ?? 0,
            'synced_to_backend': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      return;
    }
    if (kind == 'purchase_order') {
      final uuid = 'remote-${record['remoteId']}';
      final exists = await db.query('purchase_orders',
          where: 'uuid = ?', whereArgs: [uuid], limit: 1);
      if (exists.isNotEmpty) return;
      final supplierName = payload['supplier_name']?.toString().trim() ?? '';
      final suppliers = await db.query('suppliers',
          where: 'LOWER(name) = ?',
          whereArgs: [supplierName.toLowerCase()],
          limit: 1);
      if (suppliers.isEmpty) return;
      final orderId = await db.insert('purchase_orders', {
        'uuid': uuid,
        'order_number': 'REMOTE-${record['remoteId']}',
        'supplier_id': suppliers.single['id'],
        'status': payload['status'] ?? 'draft',
        'ordered_at': payload['ordered_at'],
        'expected_at': payload['expected_at'],
        'note': payload['note'],
        'created_at': payload['created_at'] ?? DateTime.now().toIso8601String(),
        'staff_id': null,
        'staff_name': payload['staff_name'] ?? 'Another till',
        'synced_to_backend': 1,
      });
      final lines = payload['lines'];
      if (lines is List) {
        for (final rawLine in lines.whereType<Map>()) {
          final remoteProductId = rawLine['product_remote_id']?.toString();
          final products = remoteProductId == null
              ? const <Map<String, Object?>>[]
              : await db.query('products',
                  where: 'remote_id = ?',
                  whereArgs: [remoteProductId],
                  limit: 1);
          if (products.isEmpty) continue;
          await db.insert(
              'purchase_order_lines',
              {
                'uuid': 'remote-${record['remoteId']}-${rawLine['id']}',
                'purchase_order_id': orderId,
                'product_id': products.single['id'],
                'product_name': rawLine['product_name'] ?? '',
                'qty': rawLine['qty'] ?? 0,
                'unit_cost_minor': rawLine['unit_cost_minor'] ?? 0,
                'received_qty': rawLine['received_qty'] ?? 0,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    }
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
            supplierPin: r.supplierPin,
            etimsInvoiceRef: r.etimsInvoiceRef,
            inputVat: r.inputVat,
            taxEvidenceStatus: r.taxEvidenceStatus,
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
      final allocationRows = await db.query(
        'sale_return_refunds',
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
            refundAllocations:
                allocationRows.map(ReturnRefundAllocation.fromMap).toList(),
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

  /// Stock movements are append-only and can be replayed safely by the
  /// backend. Keeping the queue flag on the movement, rather than deriving it
  /// from the parent sale or receipt, also covers corrections and stocktakes.
  Future<List<StockMovement>> getUnsyncedStockMovements(
      {int limit = 500}) async {
    final rows = await (await database).query(
      'stock_movements',
      where: 'synced_to_backend = 0',
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    return rows.map(StockMovement.fromMap).toList();
  }

  Future<void> markStockMovementsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    await (await database).rawUpdate(
      'UPDATE stock_movements SET synced_to_backend = 1 WHERE id IN '
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
            buyerName: s.buyerName,
            buyerTin: s.buyerTin,
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
        CAST(COALESCE(ROUND(AVG(total)), 0) AS INTEGER) AS average_minor,
        CAST(COALESCE(SUM(vat_minor), 0) AS INTEGER) AS vat_minor,
        CAST(COALESCE(SUM(taxable_minor), 0) AS INTEGER) AS taxable_minor
      FROM sales
      ${where.clause}
    ''', where.args);
    final row = rows.first;
    final expenseWhere = <String>['status = ?'];
    final expenseArgs = <Object?>['posted'];
    if (since != null) {
      expenseWhere.add('created_at >= ?');
      expenseArgs.add(since.toIso8601String());
    }
    if (until != null) {
      expenseWhere.add('created_at < ?');
      expenseArgs.add(until.toIso8601String());
    }
    if (staffId != null) {
      expenseWhere.add('staff_id = ?');
      expenseArgs.add(staffId);
    }
    final expenseRows = await (await database).rawQuery(
      'SELECT CAST(COALESCE(SUM(amount_minor), 0) AS INTEGER) AS total_minor '
      'FROM expenses WHERE ${expenseWhere.join(' AND ')}',
      expenseArgs,
    );
    return DailyTotals(
      totalMinor: (row['total_minor'] as num?)?.toInt() ?? 0,
      profitMinor: (row['profit_minor'] as num?)?.toInt() ?? 0,
      transactions: (row['transactions'] as num?)?.toInt() ?? 0,
      // AVG is necessarily a REAL, so it is the one aggregate that cannot be
      // exact; rounded once, here, and handed on as an int like every other
      // figure in this section.
      averageMinor: (row['average_minor'] as num?)?.toInt() ?? 0,
      expensesMinor: (expenseRows.first['total_minor'] as num?)?.toInt() ?? 0,
      vatMinor: (row['vat_minor'] as num?)?.toInt() ?? 0,
      taxableMinor: (row['taxable_minor'] as num?)?.toInt() ?? 0,
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
        CAST(ROUND(SUM((COALESCE(si.taxable_minor, si.unit_price * si.qty) -
          si.unit_cost * si.qty))) AS INTEGER)
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

  /// The smallest useful explanation of one product's period total.  All
  /// figures are read from the same sale-line snapshots as [topProducts], so
  /// renaming a catalogue product cannot rewrite historical analytics.
  Future<ProductDrilldownSnapshot> productDrilldown({
    required int productId,
    required DateTime since,
    DateTime? until,
    int? staffId,
  }) async {
    final where = _salesRangeWhere(
      since: since,
      until: until,
      staffId: staffId,
    );
    final db = await database;
    final summary = await db.rawQuery('''
      SELECT MAX(si.product_name) AS product_name,
             SUM(si.qty) AS units,
             CAST(ROUND(SUM(si.unit_price * si.qty)) AS INTEGER) AS revenue_minor,
             CAST(ROUND(SUM((COALESCE(si.taxable_minor, si.unit_price * si.qty) -
               si.unit_cost * si.qty))) AS INTEGER) AS profit_minor,
             COUNT(DISTINCT s.id) AS transactions
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      ${where.clause} AND si.product_id = ?
    ''', [...where.args, productId]);
    final staffRows = await db.rawQuery('''
      SELECT COALESCE(s.staff_name, 'Unknown') AS staff_name,
             COUNT(DISTINCT s.id) AS transactions,
             CAST(ROUND(SUM(si.unit_price * si.qty)) AS INTEGER) AS revenue_minor
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      ${where.clause} AND si.product_id = ?
      GROUP BY s.staff_id, s.staff_name
      ORDER BY revenue_minor DESC
    ''', [...where.args, productId]);
    final paymentRows = await db.rawQuery('''
      SELECT s.payment_method, COUNT(DISTINCT s.id) AS transactions,
             CAST(ROUND(SUM(si.unit_price * si.qty)) AS INTEGER) AS sales_minor
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      ${where.clause} AND si.product_id = ?
      GROUP BY s.payment_method
      ORDER BY sales_minor DESC
    ''', [...where.args, productId]);
    final hourlyRows = await db.rawQuery('''
      SELECT CAST(strftime('%H', s.created_at) AS INTEGER) AS hour,
             SUM(si.qty) AS units,
             COUNT(DISTINCT s.id) AS transactions,
             CAST(ROUND(SUM(si.unit_price * si.qty)) AS INTEGER) AS sales_minor
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      ${where.clause} AND si.product_id = ?
      GROUP BY hour
      ORDER BY hour
    ''', [...where.args, productId]);
    final dailyRows = await db.rawQuery('''
      SELECT strftime('%Y-%m-%d', s.created_at) AS day,
             CAST(ROUND(SUM(si.unit_price * si.qty)) AS INTEGER) AS sales_minor,
             CAST(ROUND(SUM((COALESCE(si.taxable_minor, si.unit_price * si.qty) -
               si.unit_cost * si.qty))) AS INTEGER) AS profit_minor,
             COUNT(DISTINCT s.id) AS transactions
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      ${where.clause} AND si.product_id = ?
      GROUP BY day
      ORDER BY day
    ''', [...where.args, productId]);
    final recordRows = await db.rawQuery('''
      SELECT s.id AS sale_id, s.created_at, s.staff_name, s.payment_method,
             s.total AS sale_total,
             CAST(ROUND(SUM(si.unit_price * si.qty)) AS INTEGER) AS product_sales
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      ${where.clause} AND si.product_id = ?
      GROUP BY s.id, s.created_at, s.staff_name, s.payment_method, s.total
      ORDER BY s.created_at DESC, s.id DESC
      LIMIT 200
    ''', [...where.args, productId]);
    final companionRows = await db.rawQuery('''
      SELECT si2.product_id, MAX(si2.product_name) AS product_name,
             COUNT(DISTINCT s.id) AS baskets, SUM(si2.qty) AS units
      FROM sale_items si1
      JOIN sales s ON s.id = si1.sale_id
      JOIN sale_items si2 ON si2.sale_id = si1.sale_id
      ${where.clause} AND si1.product_id = ?
        AND si2.product_id IS NOT NULL AND si2.product_id != ?
      GROUP BY si2.product_id
      ORDER BY baskets DESC, units DESC
      LIMIT 5
    ''', [...where.args, productId, productId]);
    final movementRows = await db.rawQuery('''
      SELECT * FROM stock_movements
      WHERE product_id = ? AND created_at >= ? AND created_at < ?
      ORDER BY created_at DESC, id DESC
      LIMIT 200
    ''', [
      productId,
      since.toIso8601String(),
      (until ?? DateTime.now()).toIso8601String()
    ]);
    final priceRows = await getProductPriceHistory(
      productId,
      since: since,
      until: until,
    );
    final row = summary.single;
    final product = ProductSalesRow(
      productId: productId,
      productName: row['product_name'] as String? ?? '',
      units: (row['units'] as num?)?.toDouble() ?? 0,
      revenueMinor: (row['revenue_minor'] as num?)?.toInt() ?? 0,
      profitMinor: (row['profit_minor'] as num?)?.toInt() ?? 0,
    );
    return ProductDrilldownSnapshot(
      product: product,
      catalogueProduct: await getProductById(productId),
      totals: DailyTotals(
        totalMinor: product.revenueMinor,
        profitMinor: product.profitMinor,
        transactions: (row['transactions'] as num?)?.toInt() ?? 0,
        averageMinor: product.revenueMinor == 0 ||
                (row['transactions'] as num?)?.toInt() == 0
            ? 0
            : (product.revenueMinor / (row['transactions'] as num).toInt())
                .round(),
      ),
      staff: [
        for (final value in staffRows)
          (
            name: value['staff_name'] as String? ?? 'Unknown',
            transactions: (value['transactions'] as num?)?.toInt() ?? 0,
            revenueMinor: (value['revenue_minor'] as num?)?.toInt() ?? 0,
          ),
      ],
      payments: [
        for (final value in paymentRows)
          PaymentMixRow(
            method: value['payment_method'] as String? ?? 'unknown',
            salesMinor: (value['sales_minor'] as num?)?.toInt() ?? 0,
            transactions: (value['transactions'] as num?)?.toInt() ?? 0,
          ),
      ],
      priceHistory: [
        for (final value in priceRows)
          ProductPricePoint(
            recordedAt: value['recorded_at'] as String? ?? '',
            costPriceMinor: (value['cost_price'] as num?)?.toInt() ?? 0,
            sellPriceMinor: (value['sell_price'] as num?)?.toInt() ?? 0,
            reason: value['reason'] as String?,
          ),
      ],
      hourly: [
        for (final value in hourlyRows)
          ProductHourRow(
            hour: (value['hour'] as num?)?.toInt() ?? 0,
            units: (value['units'] as num?)?.toDouble() ?? 0,
            salesMinor: (value['sales_minor'] as num?)?.toInt() ?? 0,
            transactions: (value['transactions'] as num?)?.toInt() ?? 0,
          ),
      ],
      records: [
        for (final value in recordRows)
          ProductTransactionRow(
            saleId: '${value['sale_id']}',
            createdAt: value['created_at'] as String? ?? '',
            staffName: value['staff_name'] as String? ?? 'Unknown staff',
            paymentMethod: value['payment_method'] as String? ?? 'cash',
            saleTotalMinor: (value['sale_total'] as num?)?.toInt() ?? 0,
            productSalesMinor: (value['product_sales'] as num?)?.toInt() ?? 0,
          ),
      ],
      daily: [
        for (final value in dailyRows)
          DateBucket(
            day: value['day'] as String? ?? '',
            label: DateBucket.fromDay(value['day'] as String? ?? '').label,
            salesMinor: (value['sales_minor'] as num?)?.toInt() ?? 0,
            profitMinor: (value['profit_minor'] as num?)?.toInt() ?? 0,
            transactions: (value['transactions'] as num?)?.toInt() ?? 0,
          ),
      ],
      boughtTogether: [
        for (final value in companionRows)
          ProductCompanionRow(
            productId: (value['product_id'] as num?)?.toInt() ?? 0,
            productName: value['product_name'] as String? ?? 'Unknown product',
            baskets: (value['baskets'] as num?)?.toInt() ?? 0,
            units: (value['units'] as num?)?.toDouble() ?? 0,
          ),
      ],
      stockTimeline: movementRows.map(StockMovement.fromMap).toList(),
    );
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

  /// Drinks' operational view over the shared sale-line and catalogue rows.
  ///
  /// `portion_ml` is a snapshot written at checkout: it covers a full bottle,
  /// a half or quarter, and an explicitly sized shot/tank serving.  Reading
  /// that snapshot keeps renamed products and later catalogue edits from
  /// changing historical litres sold.  No Drinks-only sales writer exists.
  Future<DrinksAnalyticsSnapshot> drinksAnalytics({
    required DateTime since,
    DateTime? until,
    int? staffId,
  }) async {
    final db = await database;
    final salesWhere = _salesRangeWhere(
      since: since,
      until: until,
      staffId: staffId,
    );
    final salesRows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN si.portion_ml > 0
          THEN si.portion_ml * si.qty ELSE 0 END), 0) AS ml_sold,
        COALESCE(SUM(CASE WHEN si.portion_ml > 0
          THEN (si.unit_price * si.qty) - COALESCE(si.discount_minor, 0)
          ELSE 0 END), 0) AS pour_sales_minor,
        COALESCE(SUM(CASE WHEN si.portion_ml > 0
          THEN si.unit_cost * si.qty ELSE 0 END), 0) AS pour_cost_minor,
        COALESCE(SUM(CASE WHEN si.portion_ml > 0 THEN 1 ELSE 0 END), 0)
          AS measured_lines
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      ${salesWhere.clause}
    ''', salesWhere.args);

    final heldWhere = <String>["status = 'held'"];
    final heldArgs = <Object?>[];
    if (staffId != null) {
      heldWhere.add('staff_id = ?');
      heldArgs.add(staffId);
    }
    final heldRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM held_carts WHERE ${heldWhere.join(' AND ')}',
      heldArgs,
    );

    final tankRows = await db.rawQuery('''
      SELECT name, stock_qty, bottle_ml
      FROM products
      WHERE active = 1 AND category = 'Tanks'
      ORDER BY name ASC
    ''');

    final movementRows = await db.rawQuery('''
      SELECT sm.movement_type, sm.qty_delta, sm.unit_cost_minor,
             p.bottle_ml
      FROM stock_movements sm
      JOIN products p ON p.id = sm.product_id
      WHERE sm.created_at >= ? AND sm.created_at < ?
        AND sm.movement_type IN ('writeoff', 'count')
        AND p.category = 'Tanks'
    ''', [
      since.toIso8601String(),
      (until ?? DateTime.now()).toIso8601String(),
    ]);
    var wasteMl = 0.0;
    var wasteValueMinor = 0;
    var dipVarianceMl = 0.0;
    for (final movement in movementRows) {
      final qty = (movement['qty_delta'] as num?)?.toDouble() ?? 0;
      final bottleMl = (movement['bottle_ml'] as num?)?.toDouble() ?? 0;
      if (movement['movement_type'] == StockMovementType.writeoff.wire) {
        wasteMl += -qty * bottleMl;
        final unitCost = (movement['unit_cost_minor'] as num?)?.toDouble() ?? 0;
        wasteValueMinor += (-qty * unitCost).round();
      } else {
        dipVarianceMl += qty * bottleMl;
      }
    }

    final row = salesRows.first;
    return DrinksAnalyticsSnapshot(
      litresSold: ((row['ml_sold'] as num?)?.toDouble() ?? 0) / 1000,
      pourSalesMinor: (row['pour_sales_minor'] as num?)?.round() ?? 0,
      pourCostMinor: (row['pour_cost_minor'] as num?)?.round() ?? 0,
      measuredLines: (row['measured_lines'] as num?)?.toInt() ?? 0,
      openTabs: (heldRows.first['count'] as num?)?.toInt() ?? 0,
      tanks: [
        for (final tank in tankRows)
          DrinkTankLevel(
            name: tank['name'] as String? ?? 'Unnamed tank',
            tankCount: (tank['stock_qty'] as num?)?.toDouble() ?? 0,
            litresRemaining: ((tank['stock_qty'] as num?)?.toDouble() ?? 0) *
                ((tank['bottle_ml'] as num?)?.toDouble() ?? 0) /
                1000,
          ),
      ],
      wasteLitres: wasteMl / 1000,
      wasteValueMinor: wasteValueMinor,
      dipVarianceLitres: dipVarianceMl / 1000,
    );
  }

  /// Takings per calendar day from [since] through the day containing [until].
  ///
  /// The range is filled in, so a day with no sales is a zero bar rather than a
  /// missing one: "we shut on Tuesday" is exactly the thing an owner is looking
  /// for, and dropping the day would erase it.
  Future<List<DateBucket>> salesByDay({
    required DateTime since,
    DateTime? until,
    int? staffId,
  }) async {
    final from = DateTime(since.year, since.month, since.day);
    final end = until ?? DateTime.now();
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
    final endDay = DateTime(end.year, end.month, end.day);
    final endExclusive =
        (end == endDay) ? endDay : DateTime(end.year, end.month, end.day + 1);
    final where = _salesRangeWhere(since: from, until: end, staffId: staffId);
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
        cursor.isBefore(endExclusive);
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
    DateTime? until,
    int? staffId,
  }) async {
    final where =
        _salesRangeWhere(since: since, until: until, staffId: staffId);
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

  /// Products with remaining dated stock that is expired or expires soon.
  ///
  /// This is deliberately a bounded, indexed batch query rather than loading
  /// every product and every batch into Dart. It is an operational warning, not
  /// a tax status, and remains available offline.
  Future<List<Product>> getExpiringProducts({int days = 7}) async {
    if (days < 0) throw ArgumentError.value(days, 'days');
    final now = DateTime.now();
    final until = now.add(Duration(days: days)).toIso8601String();
    final rows = await (await database).rawQuery('''
      SELECT p.*
      FROM products p
      JOIN stock_batches b ON b.product_id = p.id
      WHERE p.active = 1
        AND b.qty_remaining > 0 AND b.status = 'active'
        AND b.expires_at <= ?
      GROUP BY p.id
      ORDER BY MIN(b.expires_at) ASC, p.name ASC
    ''', [until]);
    return rows.map(Product.fromMap).toList();
  }

  Future<List<Product>> getExpiredProducts() async {
    final now = DateTime.now().toIso8601String();
    final rows = await (await database).rawQuery('''
      SELECT p.* FROM products p
      JOIN stock_batches b ON b.product_id = p.id
      WHERE p.active = 1 AND b.qty_remaining > 0 AND b.status = 'active'
        AND b.expires_at < ?
      GROUP BY p.id
      ORDER BY MIN(b.expires_at) ASC, p.name ASC
    ''', [now]);
    return rows.map(Product.fromMap).toList();
  }

  /// Batch rows for the product detail screen. Kept as maps because the
  /// detail view needs the audit fields as well as the quantity.
  Future<List<Map<String, dynamic>>> getProductBatches(int productId,
      {int? variantId}) async {
    final db = await database;
    return db.query('stock_batches',
        where: variantId == null
            ? 'product_id = ? AND variant_id IS NULL'
            : 'product_id = ? AND variant_id = ?',
        whereArgs: variantId == null ? [productId] : [productId, variantId],
        orderBy: 'expires_at ASC, id ASC');
  }

  /// Writes off a batch (or part of it) without changing the aggregate ledger
  /// outside the same transaction. This is the manager/owner operation behind
  /// the expired-stock dashboard action; there is deliberately no override for
  /// selling an expired batch.
  Future<void> writeOffBatch({
    required int batchId,
    required String staffName,
    int? staffId,
    double? quantity,
    String reason = 'Expired stock',
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('stock_batches',
          where: 'id = ?', whereArgs: [batchId], limit: 1);
      if (rows.isEmpty) throw StateError('Batch not found');
      final row = rows.first;
      final available = (row['qty_remaining'] as num).toDouble();
      final qty = quantity ?? available;
      if (qty <= 0 || qty > available + _qtyEpsilon) {
        throw StateError('Write-off quantity exceeds the batch balance');
      }
      final productId = row['product_id'] as int;
      final variantId = (row['variant_id'] as num?)?.toInt();
      await txn.rawUpdate(
          'UPDATE stock_batches SET qty_remaining = ?, status = ? WHERE id = ?',
          [
            available - qty,
            available - qty <= _qtyEpsilon ? 'written_off' : 'active',
            batchId
          ]);
      if (variantId != null) {
        await txn.rawUpdate(
            'UPDATE product_variants SET stock_qty = MAX(0, stock_qty - ?) WHERE id = ?',
            [qty, variantId]);
        await txn.rawUpdate(
            'UPDATE products SET stock_qty = (SELECT COALESCE(SUM(stock_qty), 0) '
            'FROM product_variants WHERE product_id = ? AND active = 1), updated_at = ? '
            'WHERE id = ?',
            [productId, DateTime.now().toIso8601String(), productId]);
      } else {
        await txn.rawUpdate(
            'UPDATE products SET stock_qty = MAX(0, stock_qty - ?), updated_at = ? WHERE id = ?',
            [qty, DateTime.now().toIso8601String(), productId]);
      }
      final balance = variantId == null
          ? await _productBalanceAfter(txn, productId)
          : await _variantBalanceAfter(txn, variantId);
      await _writeStockMovement(
        txn,
        productId: productId,
        variantId: variantId,
        type: StockMovementType.writeoff,
        qtyDelta: -qty,
        unitCostMinor: (row['unit_cost_minor'] as num?)?.toInt() ?? 0,
        batchId: batchId,
        staffId: staffId,
        staffName: staffName,
        note: reason.trim().isEmpty ? 'Expired stock' : reason.trim(),
        balanceAfter: balance,
      );
    });
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

  /// A read-only X report for the currently open shift. It deliberately does
  /// not allocate a number or write anything: unlike Z, it is a live peek.
  Future<Map<String, Object?>> getXReport(Shift shift) async {
    final end = DateTime.now().toIso8601String();
    final sales = await (await database).rawQuery(
      '''SELECT COUNT(*) AS sale_count,
                COALESCE(SUM(total), 0) AS gross_minor,
                COALESCE(SUM(profit), 0) AS profit_minor
         FROM sales
         WHERE staff_id = ? AND created_at >= ? AND created_at < ?''',
      [shift.staffId, shift.startTime, end],
    );
    final payments = await (await database).rawQuery(
      '''SELECT payment_method, COALESCE(SUM(total), 0) AS total_minor
         FROM sales
         WHERE staff_id = ? AND created_at >= ? AND created_at < ?
         GROUP BY payment_method''',
      [shift.staffId, shift.startTime, end],
    );
    final summary = sales.single;
    return <String, Object?>{
      'sale_count': (summary['sale_count'] as num).toInt(),
      'gross_minor': (summary['gross_minor'] as num).toInt(),
      'profit_minor': (summary['profit_minor'] as num).toInt(),
      'payment_mix': <String, int>{
        for (final row in payments)
          row['payment_method'] as String: (row['total_minor'] as num).toInt(),
      },
    };
  }

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

  /// Starts a physical count from a stable snapshot. Products with active
  /// variants are counted at variant level; their derived parent balance is
  /// never counted twice.
  Future<int> startStockCount({
    required String uuid,
    required String staffName,
    int? staffId,
    bool blind = false,
    bool freeze = false,
    String? name,
    String scopeType = 'all',
    String? scopeRef,
    String salesMode = 'keep_selling',
    String? note,
  }) async {
    final db = await database;
    final startedAt = DateTime.now().toIso8601String();
    return db.transaction<int>((txn) async {
      final countId = await txn.insert('stock_counts', {
        'uuid': uuid,
        'started_at': startedAt,
        'name': name,
        'scope_type': scopeType,
        'scope_ref': scopeRef,
        'sales_mode': salesMode,
        'note': note,
        'blind': blind ? 1 : 0,
        'freeze': freeze ? 1 : 0,
        'staff_id': staffId,
        'staff_name': staffName,
      });
      if (scopeType != 'all' && scopeType != 'tanks') {
        throw ArgumentError.value(scopeType, 'scopeType');
      }
      final products = await txn.query(
        'products',
        where: scopeType == 'tanks'
            ? "active = 1 AND category = 'Tanks'"
            : 'active = 1',
      );
      for (final product in products) {
        final productId = product['id'] as int;
        final tracksVariants = (product['track_variants'] as int? ?? 0) == 1;
        final variants = tracksVariants
            ? await txn.query('product_variants',
                where: 'product_id = ? AND active = 1',
                whereArgs: [productId],
                orderBy: 'position, id')
            : const <Map<String, Object?>>[];
        if (variants.isEmpty) {
          await txn.insert('stock_count_lines', {
            'uuid': _newUuid(),
            'count_id': countId,
            'product_id': productId,
            'product_name': product['name'] as String? ?? '',
            'expected_qty': (product['stock_qty'] as num?)?.toDouble() ?? 0,
          });
        } else {
          for (final variant in variants) {
            await txn.insert('stock_count_lines', {
              'uuid': _newUuid(),
              'count_id': countId,
              'product_id': productId,
              'variant_id': variant['id'] as int,
              'product_name':
                  '${product['name'] as String? ?? ''} · ${variant['name'] as String? ?? ''}',
              'expected_qty': (variant['stock_qty'] as num?)?.toDouble() ?? 0,
            });
          }
        }
      }
      return countId;
    });
  }

  Future<List<Map<String, dynamic>>> getStockCountLines(int countId) async =>
      (await database).query('stock_count_lines',
          where: 'count_id = ?', whereArgs: [countId], orderBy: 'id');

  Future<Map<String, dynamic>?> getInProgressStockCount() async {
    final rows = await (await database).query(
      'stock_counts',
      where: "status = 'in_progress'",
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getStockCountHistory(
          {int limit = 20}) async =>
      (await database).query(
        'stock_counts',
        where: "status != 'in_progress'",
        orderBy: 'COALESCE(completed_at, started_at) DESC',
        limit: limit,
      );

  Future<void> clearStockCountLine(int lineId) async {
    await (await database).update(
      'stock_count_lines',
      {
        'counted_qty': null,
        'counted_at': null,
        'recount_required': 1,
      },
      where: 'id = ?',
      whereArgs: [lineId],
    );
  }

  Future<void> recordStockCountLine({
    required int lineId,
    required double countedQty,
    bool recountRequired = false,
    int? countedBy,
    String? note,
  }) async {
    if (!countedQty.isFinite || countedQty < 0) {
      throw ArgumentError.value(countedQty, 'countedQty');
    }
    await (await database).update(
      'stock_count_lines',
      {
        'counted_qty': countedQty,
        'counted_by': countedBy,
        'recount_required': recountRequired ? 1 : 0,
        'counted_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [lineId],
    );
  }

  /// Applies all entered lines atomically. The expected-at-start balance is
  /// recovered by subtracting movements made after the count began, so sales
  /// and receipts during a count do not become shrinkage.
  Future<void> applyStockCount({
    required int countId,
    required int? staffId,
    required String staffName,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final counts = await txn.query('stock_counts',
          where: "id = ? AND status = 'in_progress'",
          whereArgs: [countId],
          limit: 1);
      if (counts.isEmpty) throw StateError('Stock count is not in progress');
      final lines = await txn.query('stock_count_lines',
          where: 'count_id = ? AND counted_qty IS NOT NULL',
          whereArgs: [countId]);
      var totalInventoryDeltaMilliunits = 0;
      for (final line in lines) {
        final productId = line['product_id'] as int;
        final variantId = line['variant_id'] as int?;
        final variantClause =
            variantId == null ? 'variant_id IS NULL' : 'variant_id = ?';
        final variantArgs = variantId == null
            ? <Object?>[productId]
            : <Object?>[productId, variantId];
        final currentRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(qty_delta), 0) AS balance FROM stock_movements '
          'WHERE product_id = ? AND $variantClause',
          variantArgs,
        );
        final countedAt = line['counted_at'] as String?;
        final afterRows = countedAt == null
            ? const <Map<String, Object?>>[]
            : await txn.rawQuery(
                'SELECT COALESCE(SUM(qty_delta), 0) AS moved FROM stock_movements '
                'WHERE product_id = ? AND $variantClause AND created_at > ?',
                [...variantArgs, countedAt],
              );
        final current = (currentRows.first['balance'] as num?)?.toDouble() ?? 0;
        final after = afterRows.isEmpty
            ? 0
            : (afterRows.first['moved'] as num?)?.toDouble() ?? 0;
        final baseline = current - after;
        final counted = (line['counted_qty'] as num).toDouble();
        final delta = counted - baseline;
        if (delta == 0) continue;
        totalInventoryDeltaMilliunits += (delta * 1000).round();
        final balanceAfter = current + delta;
        await _writeStockMovement(
          txn,
          productId: productId,
          variantId: variantId,
          type: StockMovementType.count,
          qtyDelta: delta,
          referenceType: 'stock_count',
          referenceId: countId,
          staffId: staffId,
          staffName: staffName,
          note: (counts.first['scope_type'] as String?) == 'tanks'
              ? 'Tank dip'
              : 'Physical stock count',
          balanceAfter: balanceAfter,
        );
        if (variantId == null) {
          await txn.update('products', {'stock_qty': balanceAfter},
              where: 'id = ?', whereArgs: [productId]);
        } else {
          await txn.update('product_variants', {'stock_qty': balanceAfter},
              where: 'id = ?', whereArgs: [variantId]);
        }
      }
      if (totalInventoryDeltaMilliunits != 0) {
        await _appendFinancialEvent(
          txn: txn,
          eventType: 'stock_count',
          sourceType: 'stock_count',
          sourceId: countId,
          occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
          inventoryDeltaMilliunits: totalInventoryDeltaMilliunits,
          metadata: <String, Object?>{'line_count': lines.length},
        );
      }
      await txn.update(
        'stock_counts',
        {
          'status': 'applied',
          'completed_at': DateTime.now().toIso8601String(),
          'applied_at': DateTime.now().toIso8601String(),
          'applied_by': staffId,
        },
        where: 'id = ?',
        whereArgs: [countId],
      );
    });
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
      final shiftRows = await txn.query('shifts',
          where: 'id = ? AND status = ?',
          whereArgs: [shiftId, 'open'],
          limit: 1);
      if (shiftRows.isEmpty) {
        throw StateError('Shift $shiftId is not open and cannot be reconciled');
      }
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
      final reconciliationId = await txn.insert('reconciliations', {
        'shift_id': shiftId,
        'counted_cash': countedCash.minorUnits,
        'expected_cash': expectedCash.minorUnits,
        'variance': variance.minorUnits,
        'recorded_at': now,
      });
      final sequenceRows = await txn
          .rawQuery('SELECT COALESCE(MAX(report_number), 0) + 1 AS next_number '
              'FROM shift_reports');
      final reportNumber = (sequenceRows.first['next_number'] as num).toInt();
      final startedAt = shiftRows.first['start_time'] as String;
      final salesSummary = await txn.rawQuery(
        '''SELECT COUNT(*) AS sale_count,
                  COALESCE(SUM(total), 0) AS gross_minor,
                  COALESCE(SUM(profit), 0) AS profit_minor
           FROM sales
           WHERE staff_id = ? AND created_at >= ? AND created_at < ?''',
        [shiftRows.first['staff_id'], startedAt, now],
      );
      final paymentRows = await txn.rawQuery(
        '''SELECT payment_method, COUNT(*) AS count,
                  COALESCE(SUM(total), 0) AS total_minor
           FROM sales
           WHERE staff_id = ? AND created_at >= ? AND created_at < ?
           GROUP BY payment_method''',
        [shiftRows.first['staff_id'], startedAt, now],
      );
      final taxRows = await txn.rawQuery(
        '''SELECT COALESCE(SUM(vat_minor), 0) AS vat_minor,
                  COALESCE(SUM(taxable_minor), 0) AS taxable_minor,
                  SUM(CASE WHEN etims_status = ? THEN 1 ELSE 0 END) AS etims_issued,
                  SUM(CASE WHEN etims_status = ? THEN 1 ELSE 0 END) AS etims_pending,
                  SUM(CASE WHEN etims_status = ? THEN 1 ELSE 0 END) AS etims_rejected
           FROM sales
           WHERE staff_id = ? AND created_at >= ? AND created_at < ?''',
        [
          EtimsStatus.issued,
          EtimsStatus.pending,
          EtimsStatus.rejected,
          shiftRows.first['staff_id'],
          startedAt,
          now,
        ],
      );
      final taxSummary = taxRows.single;
      await txn.insert('shift_reports', {
        'uuid': _newUuid(),
        'report_number': reportNumber,
        'shift_id': shiftId,
        'report_type': 'z',
        'snapshot_json': jsonEncode(<String, Object?>{
          'shift_id': shiftId,
          'report_number': reportNumber,
          'ended_at': now,
          'expected_cash_minor': expectedCash.minorUnits,
          'counted_cash_minor': countedCash.minorUnits,
          'variance_minor': variance.minorUnits,
          'end_float_minor': endFloatMinor,
          'reconciliation_id': reconciliationId,
          'sale_count': (salesSummary.first['sale_count'] as num).toInt(),
          'gross_minor': (salesSummary.first['gross_minor'] as num).toInt(),
          'profit_minor': (salesSummary.first['profit_minor'] as num).toInt(),
          'vat_minor': (taxSummary['vat_minor'] as num?)?.toInt() ?? 0,
          'taxable_minor': (taxSummary['taxable_minor'] as num?)?.toInt() ?? 0,
          'etims_issued': (taxSummary['etims_issued'] as num?)?.toInt() ?? 0,
          'etims_pending': (taxSummary['etims_pending'] as num?)?.toInt() ?? 0,
          'etims_rejected':
              (taxSummary['etims_rejected'] as num?)?.toInt() ?? 0,
          // KRA filing is explicitly disabled in this release. Preserve the
          // state in the immutable snapshot rather than deriving it later.
          'kra_activated': false,
          'payment_mix': <String, Object?>{
            for (final row in paymentRows)
              row['payment_method'] as String: <String, Object?>{
                'count': (row['count'] as num).toInt(),
                'total_minor': (row['total_minor'] as num).toInt(),
              },
          },
        }),
        'created_at': now,
        'staff_id': shiftRows.first['staff_id'],
        'staff_name': shiftRows.first['staff_name'],
      });
      return reconciliationId;
    });
  }

  /// Immutable Z snapshots, newest first. A closed shift has exactly one.
  Future<List<Map<String, dynamic>>> getShiftReports({int limit = 100}) async {
    return (await database)
        .query('shift_reports', orderBy: 'report_number DESC', limit: limit);
  }

  /// Returns the immutable Z snapshot for one closed shift.
  Future<Map<String, dynamic>?> getShiftReport(int shiftId) async {
    final rows = await (await database).query(
      'shift_reports',
      where: 'shift_id = ?',
      whereArgs: [shiftId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
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

    // PLUS the cash a customer paid INTO a debt in this shift (spec 7.5.3):
    // a credit repayment taken in cash became drawer money the moment it
    // was taken, and it names the shift it was taken in. A credit SALE is
    // not here — no cash moved for it — and never gets to claim a place
    // among the receipts.
    final repayments = await (await database).rawQuery(
      '''SELECT COALESCE(SUM(-amount_minor), 0) AS total_minor
         FROM credit_ledger
         WHERE shift_id = ?
           AND entry_type = 'payment'
           AND payment_method = 'cash' ''',
      [shift.id],
    );
    final repaid = (repayments.first['total_minor'] as num?)?.toInt() ?? 0;

    final expenses = await (await database).rawQuery(
      '''SELECT COALESCE(SUM(amount_minor), 0) AS total_minor
         FROM expenses
         WHERE shift_id = ?
           AND paid_from = 'till_cash'
           AND status = 'posted' ''',
      [shift.id],
    );
    final paidOut = (expenses.first['total_minor'] as num?)?.toInt() ?? 0;

    final movements = await (await database).rawQuery(
      '''SELECT COALESCE(SUM(amount_minor), 0) AS total_minor
         FROM till_movements
         WHERE shift_id = ?
           AND status = 'posted' ''',
      [shift.id],
    );
    final moved = (movements.first['total_minor'] as num?)?.toInt() ?? 0;

    return Money.fromMinor(minor - refunded + repaid - paidOut + moved);
  }

  /// Active expense categories, in the order shown to the person paying out.
  Future<List<Map<String, dynamic>>> getExpenseCategories() async {
    return (await database).query(
      'expense_categories',
      where: 'active = 1',
      orderBy: 'id ASC',
    );
  }

  Future<void> setExpenseCategoryActive({
    required int categoryId,
    required bool active,
  }) async {
    final changed = await (await database).update(
      'expense_categories',
      {'active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [categoryId],
    );
    if (changed == 0) throw StateError('Expense category not found');
  }

  Future<List<Map<String, dynamic>>> getExpensesForShift(int shiftId) async {
    return (await database).query(
      'expenses',
      where: 'shift_id = ? AND status = ?',
      whereArgs: [shiftId, 'posted'],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getExpenseHistory(
      {int limit = 100, DateTime? since, DateTime? until}) async {
    final where = <String>['e.status = ?'];
    final args = <Object?>['posted'];
    if (since != null) {
      where.add('e.created_at >= ?');
      args.add(since.toIso8601String());
    }
    if (until != null) {
      where.add('e.created_at < ?');
      args.add(until.toIso8601String());
    }
    return (await database).rawQuery(
      '''SELECT e.*, c.name AS category_name,
                e.amount_minor - COALESCE(
                  (SELECT SUM(p.amount_minor) FROM expense_payments p
                   WHERE p.expense_id = e.id), 0
                ) AS remaining_payable_minor
         FROM expenses e
         LEFT JOIN expense_categories c ON c.id = e.category_id
         WHERE ${where.join(' AND ')}
         ORDER BY e.created_at DESC
         LIMIT ?''',
      [...args, limit],
    );
  }

  Future<Map<String, int>> expectedCashBreakdown(Shift shift) async {
    final since = DateTime.parse(shift.startTime).toIso8601String();
    final until = (shift.endTime == null || shift.endTime!.isEmpty
            ? DateTime.now()
            : DateTime.parse(shift.endTime!))
        .toIso8601String();
    Future<int> one(String sql, List<Object?> args) async {
      final rows = await (await database).rawQuery(sql, args);
      return (rows.first['total_minor'] as num?)?.toInt() ?? 0;
    }

    return {
      'cash_sales': await one(
        "SELECT COALESCE(SUM(total), 0) AS total_minor FROM sales WHERE staff_id = ? AND created_at >= ? AND created_at < ? AND payment_method = 'cash' AND payment_verified = 1",
        [shift.staffId, since, until],
      ),
      'cash_refunds': await one(
        "SELECT COALESCE(SUM(total), 0) AS total_minor FROM sale_returns WHERE shift_id = ? AND refund_method = 'cash'",
        [shift.id],
      ),
      'credit_repayments': await one(
        "SELECT COALESCE(SUM(-amount_minor), 0) AS total_minor FROM credit_ledger WHERE shift_id = ? AND entry_type = 'payment' AND payment_method = 'cash'",
        [shift.id],
      ),
      'till_expenses': await one(
        "SELECT COALESCE(SUM(amount_minor), 0) AS total_minor FROM expenses WHERE shift_id = ? AND paid_from = 'till_cash' AND status = 'posted'",
        [shift.id],
      ),
      'till_movements': await one(
        "SELECT COALESCE(SUM(amount_minor), 0) AS total_minor FROM till_movements WHERE shift_id = ? AND status = 'posted'",
        [shift.id],
      ),
    };
  }

  Future<List<Map<String, dynamic>>> getTillMovementsForShift(
      int shiftId) async {
    return (await database).query(
      'till_movements',
      where: 'shift_id = ? AND status = ?',
      whereArgs: [shiftId, 'posted'],
      orderBy: 'created_at DESC',
    );
  }

  /// Offline cash-control rows waiting for the tenant-scoped server mirror.
  Future<List<Map<String, dynamic>>> getUnsyncedExpenses(
      {int limit = 200}) async {
    return (await database).query(
      'expenses',
      where: 'synced_to_backend = 0',
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
  }

  Future<void> markExpensesSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.rawUpdate(
      'UPDATE expenses SET synced_to_backend = 1 WHERE id IN '
      '(${List.filled(ids.length, '?').join(',')})',
      ids,
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedTillMovements(
      {int limit = 200}) async {
    return (await database).query(
      'till_movements',
      where: 'synced_to_backend = 0',
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
  }

  Future<void> markTillMovementsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.rawUpdate(
      'UPDATE till_movements SET synced_to_backend = 1 WHERE id IN '
      '(${List.filled(ids.length, '?').join(',')})',
      ids,
    );
  }

  /// Counts local rows waiting for an online acknowledgement without loading
  /// queue payloads into the Sync Center.
  Future<Map<String, int>> unsyncedOperationalCounts() async {
    final db = await database;
    final result = <String, int>{};
    for (final table in <String>[
      'sales',
      'shifts',
      'stock_receipts',
      'sale_returns',
      'stock_movements',
      'shot_cups',
      'expenses',
      'till_movements',
      'drawer_events',
    ]) {
      final rows = await db.rawQuery(
          'SELECT COUNT(*) AS count FROM $table WHERE synced_to_backend = 0');
      result[table] = (rows.first['count'] as num?)?.toInt() ?? 0;
    }
    return result;
  }

  /// Stores a server-confirmed operational row without pretending its local
  /// foreign keys are valid on this device. A shift, category, or product id
  /// belongs to the originating till; the payload remains the authoritative
  /// cross-device mirror and the remote id makes retries idempotent.
  Future<void> mergeRemoteOperationalRecord({
    required String remoteId,
    required String kind,
    required Map<String, dynamic> payload,
    String? deviceId,
    int? localId,
    String? createdAt,
    String? updatedAt,
  }) async {
    if (remoteId.trim().isEmpty || kind.trim().isEmpty) return;
    final now = DateTime.now().toIso8601String();
    await (await database).insert(
      'remote_operational_records',
      <String, Object?>{
        'remote_id': remoteId,
        'kind': kind,
        'device_id': deviceId,
        'local_id': localId,
        'payload_json': jsonEncode(payload),
        'created_at': createdAt ?? now,
        'updated_at': updatedAt ?? now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, int>> remoteOperationalCounts() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT kind, COUNT(*) AS count FROM remote_operational_records GROUP BY kind');
    return <String, int>{
      for (final row in rows)
        row['kind'] as String: (row['count'] as num?)?.toInt() ?? 0,
    };
  }

  /// Records an online rejection that needs a human decision. A stock race is
  /// not a reason to discard a sale: the sale stays queued, while this row
  /// makes the conflict visible after the sync request has finished.
  Future<void> recordSyncConflict({
    required String uuid,
    required String kind,
    int? localId,
    String? deviceId,
    required String reason,
    String? payloadJson,
  }) async {
    if (uuid.trim().isEmpty || kind.trim().isEmpty) return;
    await (await database).insert(
      'sync_conflicts',
      <String, Object?>{
        'uuid': uuid,
        'kind': kind,
        'local_id': localId,
        'device_id': deviceId,
        'reason': reason,
        'payload_json': payloadJson,
        'created_at': DateTime.now().toIso8601String(),
        'resolved_at': null,
        'resolution': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getOpenSyncConflicts({
    int limit = 100,
  }) async {
    final rows = await (await database).query(
      'sync_conflicts',
      where: 'resolved_at IS NULL',
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<int> countOpenSyncConflicts() async {
    final rows = await (await database).rawQuery(
        'SELECT COUNT(*) AS count FROM sync_conflicts WHERE resolved_at IS NULL');
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> resolveSyncConflict(String uuid, String resolution) async {
    final value = resolution.trim();
    if (uuid.trim().isEmpty || value.isEmpty) return;
    await (await database).update(
      'sync_conflicts',
      {
        'resolved_at': DateTime.now().toIso8601String(),
        'resolution': value,
      },
      where: 'uuid = ? AND resolved_at IS NULL',
      whereArgs: [uuid],
    );
  }

  /// Closes a remotely resolved sale conflict without deleting the local
  /// receipt. The sale remains part of the till audit ledger but is no longer
  /// retried by the bounded upload queue.
  Future<void> resolveSaleSyncConflict({
    required String uuid,
    required int localId,
    required String resolution,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('sales', {'synced_to_backend': 1},
          where: 'id = ?', whereArgs: [localId]);
      await txn.update(
        'sync_conflicts',
        {
          'resolved_at': DateTime.now().toIso8601String(),
          'resolution': resolution,
        },
        where: 'uuid = ? AND resolved_at IS NULL',
        whereArgs: [uuid],
      );
    });
  }

  /// Records a payout atomically. Till cash must belong to an open shift so
  /// the shift-close figure can explain where it went.
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
    if (uuid.trim().isEmpty) throw ArgumentError.value(uuid, 'uuid');
    if (amount.minorUnits <= 0) {
      throw StateError('An expense must be more than zero');
    }
    if (paidFrom != 'till_cash' &&
        paidFrom != 'other' &&
        paidFrom != 'payable') {
      throw StateError('An expense is paid from till cash, elsewhere or later');
    }
    final db = await database;
    return db.transaction<int>((txn) async {
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
      await _appendFinancialEvent(
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
    });
  }

  /// Pays an expense that was recorded against a payable. The payment is a
  /// separate append-only event, so it reduces cash and the payable without
  /// recognizing the operating expense a second time.
  Future<int> recordExpensePayment({
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
    final db = await database;
    return db.transaction<int>((txn) async {
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
      await _appendFinancialEvent(
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
    });
  }

  /// Voids a posted expense without deleting its audit trail. Till-paid
  /// expenses may only be voided while their shift is open; a closed shift is
  /// an immutable reconciliation record.
  Future<void> voidExpense(int expenseId) async {
    final db = await database;
    await db.transaction((txn) async {
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
      await _appendFinancialEvent(
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
    });
  }

  /// Records cash entering or leaving a shift. [amount] is signed: positive
  /// for cash-in and negative for a cash drop or float correction out.
  Future<int> createCostPool({
    required String uuid,
    required String name,
    required String poolType,
    String? note,
  }) async {
    if (uuid.trim().isEmpty || name.trim().isEmpty) {
      throw StateError('A cost pool needs an id and a name');
    }
    if (poolType != 'lot' && poolType != 'rolling_stock') {
      throw StateError('A cost pool is a lot or rolling stock');
    }
    return (await database).insert('cost_pools', {
      'uuid': uuid,
      'name': name.trim(),
      'pool_type': poolType,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Open-profile records are read through the database boundary so the
  /// profile tools do not become a second source of truth.
  Future<List<Map<String, dynamic>>> getCostPools() async =>
      (await database).query('cost_pools', orderBy: 'created_at DESC, id DESC');

  Future<List<Map<String, dynamic>>> getCostPoolEntries(int poolId) async =>
      (await database).query('cost_pool_entries',
          where: 'pool_id = ?',
          whereArgs: [poolId],
          orderBy: 'created_at DESC, id DESC');

  Future<List<Map<String, dynamic>>> getOpenJobs() async =>
      (await database).query('jobs', orderBy: 'created_at DESC, id DESC');

  Future<List<Map<String, dynamic>>> getJobCosts(int jobId) async =>
      (await database).query('job_costs',
          where: 'job_id = ?',
          whereArgs: [jobId],
          orderBy: 'created_at DESC, id DESC');

  Future<List<Map<String, dynamic>>> getJobPayments(int jobId) async =>
      (await database).query('job_payments',
          where: 'job_id = ?',
          whereArgs: [jobId],
          orderBy: 'created_at DESC, id DESC');

  Future<List<Map<String, dynamic>>> getOwnerTransactions() async =>
      (await database)
          .query('owner_transactions', orderBy: 'created_at DESC, id DESC');

  /// Records a money-first Open sale without inventing an item, stock cost, or
  /// tax figure. It is still a normal sale ledger row, so sales, cash and
  /// analytics see it through the same financial-event contract as checkout.
  ///
  /// Open's quick sale is intentionally limited to confirmed tender methods;
  /// credit sales continue through the customer-aware checkout flow.
  Future<int> recordOpenQuickSale({
    required Money amount,
    required String paymentMethod,
    required String staffName,
    int? staffId,
    String? paymentReference,
  }) async {
    if (amount.minorUnits <= 0) {
      throw StateError('A quick sale must be more than zero');
    }
    if (!<String>{'cash', 'mpesa', 'bank_transfer'}.contains(paymentMethod)) {
      throw StateError('Unsupported quick-sale payment method');
    }
    final db = await database;
    return db.transaction<int>((txn) async {
      if (paymentMethod == 'cash') {
        final shifts = await txn.query('shifts',
            where: 'status = ?',
            whereArgs: ['open'],
            orderBy: 'start_time DESC',
            limit: 1);
        if (shifts.isEmpty) throw StateError('Open a shift before taking cash');
      }
      final now = DateTime.now().toIso8601String();
      final saleId = await txn.insert('sales', <String, Object?>{
        'staff_name': staffName.trim().isEmpty ? 'Open business' : staffName,
        'staff_id': staffId,
        'total': amount.minorUnits,
        'profit': 0,
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
        'uuid': _newUuid(),
        'sale_id': saleId,
        'method': paymentMethod,
        'amount_minor': amount.minorUnits,
        'tendered_minor': amount.minorUnits,
        'change_minor': 0,
        'reference': paymentReference,
        'status': 'confirmed',
        'created_at': now,
      });
      await _appendFinancialEvent(
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
    });
  }

  Future<int> addCostPoolEntry({
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
    final db = await database;
    return db.transaction<int>((txn) async {
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
      await _appendFinancialEvent(
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
    });
  }

  Future<int> allocateCostPoolToSale({
    required int poolId,
    required int saleId,
    required Money amount,
  }) async {
    if (amount.minorUnits <= 0) {
      throw StateError('A pool allocation must be more than zero');
    }
    final db = await database;
    return db.transaction<int>((txn) async {
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
      await _appendFinancialEvent(
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
    });
  }

  Future<int> createJob({
    required String uuid,
    required String title,
    String? customerName,
    Money? quote,
    DateTime? dueAt,
  }) async {
    if (uuid.trim().isEmpty || title.trim().isEmpty) {
      throw StateError('A job needs an id and a title');
    }
    return (await database).insert('jobs', {
      'uuid': uuid,
      'customer_name': customerName,
      'title': title.trim(),
      'quote_minor': quote?.minorUnits,
      'due_at': dueAt?.toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> addJobCost({
    required String uuid,
    required int jobId,
    required String costType,
    required Money amount,
    String paidFrom = 'other',
    String? description,
  }) async {
    const costTypes = <String>{'materials', 'helper', 'transport', 'other'};
    if (!costTypes.contains(costType)) throw StateError('Unknown job cost');
    if (paidFrom != 'till_cash' &&
        paidFrom != 'other' &&
        paidFrom != 'credit') {
      throw StateError('A job cost is paid from cash, elsewhere or credit');
    }
    if (amount.minorUnits <= 0) {
      throw StateError('A job cost must be more than zero');
    }
    final db = await database;
    return db.transaction<int>((txn) async {
      final jobs = await txn.query('jobs',
          where: "id = ? AND status != 'closed'", whereArgs: [jobId], limit: 1);
      if (jobs.isEmpty) throw StateError('Job not found or closed');
      final costId = await txn.insert('job_costs', {
        'uuid': uuid,
        'job_id': jobId,
        'cost_type': costType,
        'amount_minor': amount.minorUnits,
        'paid_from': paidFrom,
        'description': description,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _appendFinancialEvent(
        txn: txn,
        eventType: 'job_cost',
        sourceType: 'job_cost',
        sourceId: costId,
        occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
        cogsMinor: amount.minorUnits,
        cashOutMinor: paidFrom == 'till_cash' ? amount.minorUnits : 0,
        payableDeltaMinor: paidFrom == 'credit' ? amount.minorUnits : 0,
        metadata: <String, Object?>{
          'job_id': jobId,
          'cost_type': costType,
          'paid_from': paidFrom,
        },
      );
      return costId;
    });
  }

  /// Completes a job and recognizes its final price exactly once.
  ///
  /// Payments taken while the job was open are customer deposits. Completion
  /// converts that liability into earned revenue and leaves only the unpaid
  /// balance as a receivable. The job row and the normalized event are written
  /// atomically so reports cannot observe an earned job without its source.
  Future<void> completeJob({
    required int jobId,
    required Money finalPrice,
  }) async {
    if (finalPrice.minorUnits <= 0) {
      throw StateError('A completed job must have a final price');
    }
    final db = await database;
    await db.transaction((txn) async {
      final jobs = await txn.query(
        'jobs',
        where: "id = ? AND status = 'open'",
        whereArgs: [jobId],
        limit: 1,
      );
      if (jobs.isEmpty) throw StateError('Job not found or already closed');
      final depositsRows = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount_minor), 0) AS total FROM job_payments '
        'WHERE job_id = ?',
        [jobId],
      );
      final deposits = (depositsRows.first['total'] as num?)?.toInt() ?? 0;
      if (deposits > finalPrice.minorUnits) {
        throw StateError('The final price cannot be below collected deposits');
      }
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'jobs',
        {
          'final_price_minor': finalPrice.minorUnits,
          'status': 'closed',
          'closed_at': now,
        },
        where: 'id = ?',
        whereArgs: [jobId],
      );
      await _appendFinancialEvent(
        txn: txn,
        eventType: 'job_completion',
        sourceType: 'job',
        sourceId: jobId,
        occurredAtUtc: DateTime.parse(now).toUtc().toIso8601String(),
        revenueMinor: finalPrice.minorUnits,
        receivableDeltaMinor: finalPrice.minorUnits - deposits,
        customerDepositDeltaMinor: -deposits,
        metadata: <String, Object?>{
          'final_price_minor': finalPrice.minorUnits,
          'deposits_applied_minor': deposits,
        },
      );
    });
  }

  Future<int> recordJobPayment({
    required String uuid,
    required int jobId,
    required Money amount,
    required String paymentMethod,
    String? reference,
    int? shiftId,
  }) async {
    if (amount.minorUnits <= 0) {
      throw StateError('A job payment must be more than zero');
    }
    if (!<String>{'cash', 'mpesa', 'bank_transfer'}.contains(paymentMethod)) {
      throw StateError('Unsupported job payment method');
    }
    final db = await database;
    return db.transaction<int>((txn) async {
      final jobs = await txn.query('jobs',
          where: 'id = ?', whereArgs: [jobId], limit: 1);
      if (jobs.isEmpty) throw StateError('Job not found');
      final job = jobs.first;
      int? resolvedShiftId = shiftId;
      if (paymentMethod == 'cash') {
        if (resolvedShiftId == null) {
          final shifts = await txn.query('shifts',
              where: 'status = ?',
              whereArgs: ['open'],
              orderBy: 'start_time DESC',
              limit: 1);
          if (shifts.isEmpty) {
            throw StateError('Open a shift before taking cash');
          }
          resolvedShiftId = shifts.first['id'] as int;
        } else {
          final shifts = await txn.query('shifts',
              where: 'id = ? AND status = ?',
              whereArgs: [resolvedShiftId, 'open']);
          if (shifts.isEmpty) throw StateError('Shift is not open');
        }
      }
      final isDeposit = (job['status'] as String?) != 'closed';
      if (!isDeposit) {
        final finalPrice = (job['final_price_minor'] as num?)?.toInt();
        if (finalPrice == null) {
          throw StateError('A closed job must have a final price');
        }
        final paidRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(amount_minor), 0) AS total FROM job_payments '
          'WHERE job_id = ?',
          [jobId],
        );
        final paid = (paidRows.first['total'] as num?)?.toInt() ?? 0;
        if (paid + amount.minorUnits > finalPrice) {
          throw StateError('That payment exceeds the job balance');
        }
      }
      final paymentId = await txn.insert('job_payments', {
        'uuid': uuid,
        'job_id': jobId,
        'amount_minor': amount.minorUnits,
        'payment_method': paymentMethod,
        'reference': reference,
        'shift_id': resolvedShiftId,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _appendFinancialEvent(
        txn: txn,
        eventType: 'job_payment',
        sourceType: 'job_payment',
        sourceId: paymentId,
        occurredAtUtc: DateTime.now().toUtc().toIso8601String(),
        cashInMinor: amount.minorUnits,
        receivableDeltaMinor: isDeposit ? 0 : -amount.minorUnits,
        customerDepositDeltaMinor: isDeposit ? amount.minorUnits : 0,
        metadata: <String, Object?>{
          'job_id': jobId,
          'payment_method': paymentMethod,
          'shift_id': resolvedShiftId,
          'is_deposit': isDeposit,
        },
      );
      return paymentId;
    });
  }

  Future<int> recordOwnerTransaction({
    required String uuid,
    required String transactionType,
    required Money amount,
    required int shiftId,
    required String staffName,
    int? staffId,
    String? note,
  }) async {
    const allowed = <String>{
      'capital_in',
      'drawing',
      'loan_received',
      'loan_repayment',
    };
    if (uuid.trim().isEmpty) throw ArgumentError.value(uuid, 'uuid');
    if (!allowed.contains(transactionType)) {
      throw StateError('Unknown owner transaction');
    }
    if (amount.minorUnits <= 0) {
      throw StateError('An owner transaction must be more than zero');
    }
    final db = await database;
    return db.transaction<int>((txn) async {
      final shifts = await txn.query('shifts',
          where: 'id = ? AND status = ?', whereArgs: [shiftId, 'open']);
      if (shifts.isEmpty) throw StateError('Shift is not open');
      final now = DateTime.now().toIso8601String();
      final eventAtUtc = DateTime.now().toUtc().toIso8601String();
      final transactionId = await txn.insert('owner_transactions', {
        'uuid': uuid,
        'transaction_type': transactionType,
        'amount_minor': amount.minorUnits,
        'shift_id': shiftId,
        'staff_id': staffId,
        'staff_name': staffName,
        'note': note,
        'created_at': now,
      });
      final cashIn =
          transactionType == 'capital_in' || transactionType == 'loan_received';
      await _appendFinancialEvent(
        txn: txn,
        eventType: 'owner_transaction',
        sourceType: 'owner_transaction',
        sourceId: transactionId,
        occurredAtUtc: eventAtUtc,
        cashInMinor: cashIn ? amount.minorUnits : 0,
        cashOutMinor: cashIn ? 0 : amount.minorUnits,
        metadata: <String, Object?>{
          'transaction_type': transactionType,
          'shift_id': shiftId,
        },
      );
      return transactionId;
    });
  }

  Future<int> recordTillMovement({
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
    final db = await database;
    return db.transaction<int>((txn) async {
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
      await _appendFinancialEvent(
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
    });
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

  /// Merges a serving configuration from another till by the product it
  /// belongs to and its label. Product ids are local, so the caller resolves
  /// the remote product id before reaching this method.
  Future<void> mergeRemoteShotCup({
    required int productId,
    required String productName,
    required int capacityMl,
    required int priceMinor,
    required String label,
    required bool active,
  }) async {
    final db = await database;
    final existing = await db.query(
      'shot_cups',
      columns: ['id'],
      where: 'product_id = ? AND label = ?',
      whereArgs: [productId, label],
      limit: 1,
    );
    final values = <String, Object?>{
      'product_id': productId,
      'product_name': productName,
      'capacity_ml': capacityMl,
      'price': priceMinor,
      'label': label,
      'active': active ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
      'synced_to_backend': 1,
    };
    if (existing.isEmpty) {
      await db.insert('shot_cups', values);
    } else {
      await db.update('shot_cups', values,
          where: 'id = ?', whereArgs: [existing.first['id']]);
    }
    await db.update('products', {'unit': ProductUnit.cup.wire},
        where: 'id = ?', whereArgs: [productId]);
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
    if (query.until != null) {
      conditions.add('created_at < ?');
      args.add(query.until);
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
    AuditAction.profileChanged,
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
    this.documentType = 'sale',
    this.lastError,
  });

  final int saleId;
  final String receiptNumber;
  final int attempts;
  final DateTime createdAt;
  final String documentType;
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
