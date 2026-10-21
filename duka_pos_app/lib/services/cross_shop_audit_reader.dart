/// The owner's view of who did what, across EVERY shop on this device.
///
/// ## Why this is a reader and not a table
///
/// Each shop owns its own SQLite file — that is the isolation guarantee the
/// workspace layer exists to provide, and it is what stops shop A's takings
/// appearing in shop B's report. So a log that must answer "what happened
/// anywhere" cannot be a single table in one shop's database: it can only be
/// assembled by asking each shop in turn.
///
/// This service does exactly that, and does it the honest way — it walks the
/// local shop registry, asks each shop's own database for its own rows, and
/// restores the shop that was active when it started. Nothing is copied between
/// shops, nothing is written to a shared store, and a shop with no audit table
/// at all (one added before v18) simply contributes nothing rather than
/// failing the whole read.
///
/// It reads on the main isolate deliberately. A shop's audit log is capped
/// (see `DatabaseHelper.pruneAuditLog`) and the read is an indexed query, so
/// this is not a full-table scan; the alternative — shipping key bytes across
/// an isolate boundary per shop — would be more machinery, not less work.
library;

import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../models/audit_log.dart';
import 'workspace_service.dart';

/// One audit row, tagged with the shop it came from.
///
/// The shop name is denormalised in here rather than resolved on read, because
/// a shop can be renamed on the backend after the fact and the log should still
/// say which shop the thing happened in — the one the owner typed.
class ShopAuditEntry {
  const ShopAuditEntry({
    required this.entry,
    required this.shopName,
    required this.workspaceKey,
  });

  final AuditLogEntry entry;

  /// The shop's name, as recorded when it was added on this device.
  final String shopName;

  /// Stable identity, so a row can be traced to the database it came from.
  final String workspaceKey;
}

/// A shop's activity, or the fact that it has none.
class ShopActivity {
  const ShopActivity({
    required this.shopName,
    required this.workspaceKey,
    required this.entries,
    this.failed = false,
  });

  final String shopName;
  final String workspaceKey;
  final List<AuditLogEntry> entries;

  /// True when this shop's log could not be read at all.
  ///
  /// A whole screen that disappears because one shop's file is unreadable hides
  /// the shops that CAN be read, so a failed shop is reported as a shop with a
  /// problem rather than dropped from the list.
  final bool failed;
}

/// Reads the audit log of every shop registered on this device.
class CrossShopAuditReader {
  const CrossShopAuditReader._();

  /// Every shop's owner-relevant activity, newest-first within each shop.
  ///
  /// Shops are returned in the order the registry lists them — the original
  /// shop first, then alphabetically — because the owner's mental model is
  /// "my first shop, then the ones I added", not whatever order SQLite returns.
  ///
  /// The shop that was active when this was called is active again when it
  /// returns. That is the whole correctness requirement of a cross-shop read,
  /// and violating it would silently point the till at a different shop than
  /// the one on screen.
  ///
  /// ## Why this is gated, not merely guarded
  ///
  /// The walk takes one lock and holds it for its whole duration, so nothing
  /// else can move the process-global `DatabaseHelper` while it runs. Each shop
  /// is read through its own read-only handle, so the walk never repoints the
  /// singleton and nothing running during the walk — the auto-backup timer,
  /// an in-flight `recordSale`, the failure recorder's own write — can land
  /// in the wrong shop's database.
  static Future<List<ShopActivity>> readAllShops({
    int limitPerShop = 50,
  }) async {
    return DatabaseHelper.instance
        .withWorkspaceGate(() => _walkShops(limitPerShop: limitPerShop));
  }

  /// Tours every registered shop. Caller must already hold the workspace gate
  /// (see [DatabaseHelper.withWorkspaceGate]).
  static Future<List<ShopActivity>> _walkShops({
    required int limitPerShop,
  }) async {
    final shops = await WorkspaceServiceShops.localShops();
    // The database's OWN key, not the registry's: this read moves the database,
    // so the thing to restore is where the database was.
    final active = DatabaseHelper.instance.currentWorkspaceKey;

    final results = <ShopActivity>[];
    try {
      for (final shop in shops) {
        // Only shops whose database this device has actually created have
        // anything to say. A shop registered but never opened — one whose
        // owner tapped Verify and abandoned the flow — has no file at all.
        try {
          // Each shop gets its own read-only handle: the cross-shop tour does
          // not repoint this process-global `DatabaseHelper`, so the auto-backup
          // timer, eTIMS flush, live refresh or an in-flight sale can never run
          // against the wrong shop mid-tour.
          final path = await DatabaseHelper.databasePathFor(shop.workspaceKey);
          final file = File(path);
          if (!(await file.exists())) {
            // A registered shop whose database was never created — the owner
            // tapped Verify and abandoned the flow. It contributes nothing,
            // and it is not broken.
            results.add(ShopActivity(
              shopName: shop.shopName,
              workspaceKey: shop.workspaceKey,
              entries: const <AuditLogEntry>[],
            ));
            continue;
          }
          final db =
              await openDatabase(path, readOnly: true, singleInstance: false);
          try {
            final entries = await ownerRelevantAuditForDb(
              db,
              limit: limitPerShop,
            );
            results.add(ShopActivity(
              shopName: shop.shopName,
              workspaceKey: shop.workspaceKey,
              entries: entries,
            ));
          } finally {
            await db.close();
          }
        } catch (_) {
          // A shop that could not be read still gets a row, marked failed: an
          // owner who cannot see that a shop is unreadable will assume the
          // shop has nothing to hide.
          results.add(ShopActivity(
            shopName: shop.shopName,
            workspaceKey: shop.workspaceKey,
            entries: const <AuditLogEntry>[],
            failed: true,
          ));
        }
      }
    } finally {
      // Restore whatever shop the caller was in, even if the walk threw. This
      // is the one line that makes a cross-shop read safe to call from any
      // screen: without it, a screen that read every shop would leave the till
      // pointed at the last one it happened to visit.
      //
      // A user switch that arrives while the walk runs cannot interleave with
      // it: the switch is gated, so it either runs before the walk or is queued
      // behind it, and a queued switch lands after this restore and wins — which
      // is the right way round.
      if (DatabaseHelper.instance.currentWorkspaceKey != active) {
        await DatabaseHelper.instance.switchWorkspaceHoldingGate(active);
      }
    }
    return results;
  }

  /// Runs `ownerRelevantAudit` against a specific, already-open read-only handle.
  ///
  /// The cross-shop tour uses this instead of repointing the global
  /// `DatabaseHelper`, so a tour cannot strand the till on the wrong shop.
  static Future<List<AuditLogEntry>> ownerRelevantAuditForDb(
    Database db, {
    required int limit,
  }) async {
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

  /// The actions the owner's cross-shop view shows — sales and other noise are
  /// excluded, just as `DatabaseHelper.ownerRelevantAudit` excludes them.
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

  /// Every audit row on this device, merged and sorted newest-first.
  ///
  /// The flat view: what an owner wants when the question is "what changed
  /// recently", rather than "what changed in shop X".
  ///
  /// A thin wrapper over [mergeNewestFirst], which is the one place the ordering
  /// and the cap live — the activity screen's merged tab sorts through the same
  /// helper, so the two cannot disagree about what "newest first" means.
  static Future<List<ShopAuditEntry>> readMerged({
    int limitPerShop = 50,
    int totalLimit = 100,
  }) async =>
      mergeNewestFirst(
        shops: await readAllShops(limitPerShop: limitPerShop),
        totalLimit: totalLimit,
      );

  /// Flattens several shops' rows into one newest-first list, capped overall.
  ///
  /// Pure, so both the service's [readMerged] and the activity screen's merged
  /// tab share one ordering and one cap instead of each keeping their own.
  ///
  /// The sort is on the stored `created_at`, which is an ISO-8601 string: within
  /// one device the offset never changes, so lexicographic order is chronological
  /// order there — which is also why the tie-break is the row id rather than
  /// anything time-based.
  static List<ShopAuditEntry> mergeNewestFirst({
    required List<ShopActivity> shops,
    int totalLimit = 100,
  }) {
    final merged = <ShopAuditEntry>[
      for (final shop in shops)
        for (final entry in shop.entries)
          ShopAuditEntry(
            entry: entry,
            shopName: shop.shopName,
            workspaceKey: shop.workspaceKey,
          ),
    ];
    merged.sort((a, b) => b.entry.createdAt.compareTo(a.entry.createdAt));
    return merged.length <= totalLimit ? merged : merged.sublist(0, totalLimit);
  }

  /// How many shops on this device have any activity at all.
  ///
  /// The number the settings row shows, so an owner knows the view is worth
  /// opening before they open it.
  static Future<int> countShopsWithActivity() async {
    final perShop = await readAllShops(limitPerShop: 1);
    return perShop.where((shop) => shop.entries.isNotEmpty).length;
  }
}
