// The owner's activity view: what changed, where, and who did it.
//
// ## What this screen is for
//
// The ledger says what was sold and what the stock is. Neither says who
// changed the VAT rate at 11pm, which cashier erased a backup, or whether the
// manager who resigned still has an account that can sign in. This is the
// screen that answers those, and it answers them for EVERY shop on this
// device — an owner running two dukas from one phone should not have to switch
// shops to learn what happened in each.
//
// ## Why it is a panel built from a value
//
// The read walks every shop's own database, which is real async work with a
// real switching cost. Splitting it from the presentation means a test can
// render the whole screen from a constructed value — which is how the four
// states, the RTL mirroring and the large-text survival are checked without
// seeding three shops and their databases.

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/audit_log.dart';
import '../services/cross_shop_audit_reader.dart';
import '../services/session_refresh_mixin.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/states.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../ui/components/brand_header.dart';

enum ActivityView { merged, byShop }

class ActivityRow {
  const ActivityRow({required this.entry, required this.shopName});

  final AuditLogEntry entry;

  final String shopName;
}

class ActivitySnapshot {
  const ActivitySnapshot({required this.perShop});

  final List<ShopActivity> perShop;

  static const empty = ActivitySnapshot(perShop: <ShopActivity>[]);

  bool get isEmpty => perShop.every((shop) => shop.entries.isEmpty);

  int get totalEntries =>
      perShop.fold<int>(0, (sum, shop) => sum + shop.entries.length);

  int get shopCount => perShop.length;

  bool get anyFailed => perShop.any((shop) => shop.failed);

  List<ActivityRow> get merged => CrossShopAuditReader.mergeNewestFirst(
        shops: perShop,
      )
          .map((row) => ActivityRow(entry: row.entry, shopName: row.shopName))
          .toList();
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SessionRefresh<ActivityScreen> {
  ActivityView _view = ActivityView.merged;
  ActivitySnapshot _snapshot = ActivitySnapshot.empty;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void clearForSession() {
    _snapshot = ActivitySnapshot.empty;
    _loading = true;
    _failed = false;
  }

  @override
  Future<void> reloadFromSession() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final perShop = await CrossShopAuditReader.readAllShops();
      if (!mounted) return;
      setState(() {
        _snapshot = ActivitySnapshot(perShop: perShop);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _setView(ActivityView view) {
    if (view == _view) return;
    setState(() => _view = view);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: BrandHeader(
          title: Text(l10n.activityTitle),
        ),
      ),
      body: AdaptivePage(
        scrollable: false,
        maxContentWidth: 880,
        child: switch ((_loading, _failed)) {
          // A refresh never blanks what is already on screen: the previous
          // snapshot stays while the reload runs, so the owner keeps their place.
          (true, false) when _snapshot.perShop.isEmpty =>
            const _ActivitySkeleton(),
          (false, true) => ErrorStateView(
              message: l10n.activityLoadFailed,
              onRetry: _load,
            ),
          _ => ActivityPanel(
              snapshot: _snapshot,
              view: _view,
              onViewChanged: _setView,
              onRetry: _load,
              refreshing: _loading,
            ),
        },
      ),
    );
  }
}

class ActivityPanel extends StatelessWidget {
  const ActivityPanel({
    super.key,
    required this.snapshot,
    required this.view,
    required this.onViewChanged,
    required this.onRetry,
    this.refreshing = false,
  });

  final ActivitySnapshot snapshot;
  final ActivityView view;
  final ValueChanged<ActivityView> onViewChanged;
  final Future<void> Function() onRetry;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    // One of four states, resolved in ONE place. An empty catalogue and a
    // failed read are different sentences because they are different problems.
    if (snapshot.isEmpty) {
      return EmptyStateView(
        title: l10n.activityEmptyTitle,
        message: l10n.activityEmptyMessage,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The summary line: how many shops, how many rows.
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.activitySummary(snapshot.totalEntries, snapshot.shopCount),
            style: AppTypography.of(context).bodySmall?.copyWith(
                  color: AppColors.of(context).onSurfaceMuted,
                ),
          ),
        ),
        SizedBox(height: spacing.sm),
        // The two ways to read it. Only offered when there is more than one
        // shop: a single-shop owner has nothing to switch between.
        if (snapshot.shopCount > 1)
          Row(
            children: <Widget>[
              Expanded(
                child: _ViewSwitch(
                  label: l10n.activityViewMerged,
                  selected: view == ActivityView.merged,
                  onTap: () => onViewChanged(ActivityView.merged),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: _ViewSwitch(
                  label: l10n.activityViewByShop,
                  selected: view == ActivityView.byShop,
                  onTap: () => onViewChanged(ActivityView.byShop),
                ),
              ),
            ],
          ),
        SizedBox(height: spacing.md),
        // The refresh indicator, inline: a reloading view is still readable.
        if (refreshing)
          Padding(
            padding: EdgeInsets.only(bottom: spacing.sm),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        Expanded(
          // Pull to refresh, so the log can be re-read without leaving the
          // screen. The rows come from every shop's own database on the device,
          // which is the slowest read in the app — and a shop that cannot force
          // it has to navigate away and back to see what just happened.
          child: RefreshIndicator(
            // `onRetry` IS the reload: the panel's one reload callback.
            onRefresh: onRetry,
            child: view == ActivityView.merged
                ? _MergedList(rows: snapshot.merged)
                : _ByShopList(snapshot: snapshot),
          ),
        ),
      ],
    );
  }
}

class _MergedList extends StatelessWidget {
  const _MergedList({required this.rows});

  final List<ActivityRow> rows;

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: rows.length,
        separatorBuilder: (_, i) =>
            Divider(height: 1, color: AppColors.of(context).outline),
        itemBuilder: (_, i) => _ActivityRow(
          entry: rows[i].entry,
          shopName: rows[i].shopName,
          showShop: true,
        ),
      );
}

enum _ActivityLineKind { heading, unreadable, emptyShop, row }

class _ActivityLine {
  const _ActivityLine._({
    required this.kind,
    required this.shop,
    this.entry,
    this.index = 0,
  });

  const _ActivityLine.heading(ShopActivity shop)
      : this._(kind: _ActivityLineKind.heading, shop: shop);

  const _ActivityLine.unreadable(ShopActivity shop)
      : this._(kind: _ActivityLineKind.unreadable, shop: shop);

  const _ActivityLine.emptyShop(ShopActivity shop)
      : this._(kind: _ActivityLineKind.emptyShop, shop: shop);

  const _ActivityLine.row(ShopActivity shop, AuditLogEntry entry, int index)
      : this._(
          kind: _ActivityLineKind.row,
          shop: shop,
          entry: entry,
          index: index,
        );

  final _ActivityLineKind kind;

  final ShopActivity shop;

  final AuditLogEntry? entry;

  final int index;
}

class _ByShopList extends StatelessWidget {
  const _ByShopList({required this.snapshot});

  final ActivitySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    // Resolved to DATA, not to widgets, and once per snapshot: build() runs
    // whenever the view toggles or a snackbar appears, and flattening several
    // shops into a single list is O(all rows). The item builder then turns only
    // the visible lines into widgets.
    //
    // ONE SPREAD PER SHOP, heading first.
    //
    // Four parallel `for` loops — one for headings, then one each for the
    // unreadable/empty markers and the rows — rendered every heading before
    // every row, so all the shop names stacked at the top and the rows arrived
    // below them with nothing to attach to. Grouping is the entire point of a
    // per-shop view, so the phases are folded into one loop that keeps each
    // shop's lines together.
    final List<_ActivityLine> lines = <_ActivityLine>[
      for (final shop in snapshot.perShop)
        if (shop.failed) ...<_ActivityLine>[
          _ActivityLine.heading(shop),
          _ActivityLine.unreadable(shop),
        ] else if (shop.entries.isEmpty) ...<_ActivityLine>[
          _ActivityLine.heading(shop),
          _ActivityLine.emptyShop(shop),
        ] else ...<_ActivityLine>[
          _ActivityLine.heading(shop),
          for (var i = 0; i < shop.entries.length; i++)
            _ActivityLine.row(shop, shop.entries[i], i),
        ],
    ];

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: lines.length,
      itemBuilder: (BuildContext context, int i) {
        final _ActivityLine line = lines[i];
        switch (line.kind) {
          case _ActivityLineKind.unreadable:
            return Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.xl,
                end: spacing.xl,
                bottom: spacing.md,
              ),
              child: Text(
                l10n.activityShopUnreadableDetail,
                style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
              ),
            );
          case _ActivityLineKind.emptyShop:
            return Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.xl,
                end: spacing.xl,
                bottom: spacing.md,
              ),
              child: Text(
                l10n.activityShopEmpty,
                style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
              ),
            );
          case _ActivityLineKind.row:
            return _ActivityRow(
              entry: line.entry!,
              shopName: null,
              showDivider: line.index != line.shop.entries.length - 1,
            );
          case _ActivityLineKind.heading:
            // A shop name is a NAME, not a section eyebrow. Rendered as a real
            // heading rather than through SectionHeader, which upper-cases its
            // label — a screen that says `AMINA DUKA` in one view and
            // `Amina Duka` in the other is a screen with two names for the same
            // shop. Still a Semantics header so a screen-reader user can jump
            // between shops.
            return Semantics(
              header: true,
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: spacing.xs,
                  top: spacing.lg,
                  bottom: spacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        line.shop.shopName,
                        style: type.titleSmall,
                      ),
                    ),
                    if (line.shop.failed) ...<Widget>[
                      SizedBox(width: spacing.sm),
                      StatusChip(
                        tone: StatusTone.danger,
                        text: l10n.activityShopUnreadable,
                        dense: true,
                      ),
                    ],
                  ],
                ),
              ),
            );
        }
      },
    );
  }
}

/// One row: the icon, the sentence, the actor and the time.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.entry,
    required this.shopName,
    this.showShop = false,
    this.showDivider = true,
  });

  final AuditLogEntry entry;

  /// The shop's name, shown as a column in the merged view.
  final String? shopName;

  final bool showShop;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme type = AppTypography.of(context);

    // The tone is derived from the action, last: the glyph and the words carry
    // the state, the colour only reinforces it.
    final StatusTone tone = switch (entry.action) {
      AuditAction.backupErased ||
      AuditAction.staffRemoved ||
      AuditAction.barcodeRemoved =>
        StatusTone.danger,
      AuditAction.taxSettingsChanged ||
      AuditAction.paymentMethodChanged ||
      AuditAction.printerSaved ||
      AuditAction.staffPinReset ||
      AuditAction.backupRestored =>
        StatusTone.warning,
      AuditAction.saleRecorded ||
      AuditAction.shiftOpened ||
      AuditAction.shiftClosed =>
        StatusTone.success,
      _ => StatusTone.neutral,
    };

    final String sentence = _describe(l10n);

    return Semantics(
      container: true,
      label: showShop && shopName != null ? '$shopName, $sentence' : sentence,
      child: ExcludeSemantics(
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.xl,
                end: spacing.xl,
                top: spacing.md,
                bottom: spacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // The glyph is the first of three channels: the sentence is
                  // the second, the actor the third. Colour is never alone.
                  Container(
                    padding: EdgeInsets.all(spacing.sm),
                    decoration: BoxDecoration(
                      color: tone.container(colors),
                      borderRadius: AppShapes.of(context).controlRadius,
                    ),
                    child: Icon(tone.icon,
                        size: 18, color: tone.onContainer(colors)),
                  ),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(sentence, style: type.bodyMedium),
                        SizedBox(height: 2),
                        Text(
                          // The actor and the time, with the shop between them
                          // in the merged view: three facts in the order a
                          // reader scans them, and the shop is what makes the
                          // row answerable across a multi-shop device.
                          showShop && shopName != null
                              ? '$shopName · ${entry.actorName} · '
                                  '${_when(entry.createdAt)}'
                              : '${entry.actorName} · '
                                  '${_when(entry.createdAt)}',
                          style: type.bodySmall?.copyWith(
                            color: colors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showDivider) Divider(height: 1, color: colors.outline),
          ],
        ),
      ),
    );
  }

  String _describe(AppLocalizations l10n) {
    final String action = switch (entry.action) {
      AuditAction.productCreated => l10n.activityProductCreated,
      AuditAction.productUpdated => l10n.activityProductUpdated,
      AuditAction.productPhotoSet => l10n.activityProductPhotoSet,
      AuditAction.productPhotoRemoved => l10n.activityProductPhotoRemoved,
      AuditAction.barcodeAdded => l10n.activityBarcodeAdded,
      AuditAction.barcodeRemoved => l10n.activityBarcodeRemoved,
      AuditAction.barcodeKindChanged => l10n.activityBarcodeKindChanged,
      AuditAction.stockAdjusted => l10n.activityStockAdjusted,
      AuditAction.saleRecorded => l10n.activitySaleRecorded,
      AuditAction.shotCupSold => l10n.activityShotCupSold,
      AuditAction.staffAdded => l10n.activityStaffAdded,
      AuditAction.staffRemoved => l10n.activityStaffRemoved,
      AuditAction.staffPinReset => l10n.activityStaffPinReset,
      AuditAction.paymentMethodChanged => l10n.activityPaymentChanged,
      AuditAction.printerPaired => l10n.activityPrinterPaired,
      AuditAction.printerSaved => l10n.activityPrinterSaved,
      AuditAction.taxSettingsChanged => l10n.activityTaxChanged,
      AuditAction.syncSettingsChanged => l10n.activitySyncChanged,
      AuditAction.backupExported => l10n.activityBackupExported,
      AuditAction.backupRestored => l10n.activityBackupRestored,
      AuditAction.backupErased => l10n.activityBackupErased,
      AuditAction.shopSwitched => l10n.activityShopSwitched,
      AuditAction.shopCreated => l10n.activityShopCreated,
      AuditAction.shiftOpened => l10n.activityShiftOpened,
      AuditAction.shiftClosed => l10n.activityShiftClosed,
      AuditAction.identityLinked => l10n.activityIdentityLinked,
      AuditAction.productVariantAdded => l10n.activityVariantAdded,
      AuditAction.productVariantUpdated => l10n.activityVariantUpdated,
      AuditAction.productVariantRemoved => l10n.activityVariantRemoved,
      AuditAction.ownerPinReset => l10n.activityOwnerPinReset,
      AuditAction.accountDeleted => l10n.activityAccountDeleted,
    };
    final String detail = entry.detail?.trim() ?? '';
    return detail.isEmpty ? action : '$action — $detail';
  }

  String _when(String iso) {
    final at = DateTime.tryParse(iso);
    if (at == null) return iso;
    final now = DateTime.now();
    final difference = now.difference(at.toLocal());
    if (difference.isNegative) return iso;
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes} min ago';
    if (difference.inDays < 1) return '${difference.inHours} h ago';
    if (difference.inDays < 30) return '${difference.inDays} d ago';
    return iso.substring(0, 10);
  }
}

class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppShapes.of(context).controlRadius,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.of(context).sm),
          decoration: BoxDecoration(
            color: selected ? colors.surfaceSunken : colors.surface,
            borderRadius: AppShapes.of(context).controlRadius,
            border: Border.all(
              color: selected ? colors.accent : colors.outline,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: AppTypography.of(context).labelLarge?.copyWith(
                    color: selected ? colors.accent : colors.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    return Column(
      children: List<Widget>.generate(8, (int i) {
        return Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.xl,
            end: spacing.xl,
            top: spacing.sm,
            bottom: spacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.surfaceSunken,
                  borderRadius: AppShapes.of(context).controlRadius,
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FractionallySizedBox(
                      widthFactor: i.isEven ? 0.7 : 0.5,
                      child: Container(
                        height: 13,
                        decoration: BoxDecoration(
                          color: colors.surfaceSunken,
                          borderRadius: AppShapes.of(context).barRadius,
                        ),
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    FractionallySizedBox(
                      widthFactor: 0.4,
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors.surfaceSunken,
                          borderRadius: AppShapes.of(context).barRadius,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
