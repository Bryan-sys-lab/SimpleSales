import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/audit_log.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/audit_actor.dart';
import '../services/barcode/barcode_service.dart';
import '../services/backend_service.dart';
import '../services/live_refresh_mixin.dart';
import '../services/live_channel_service.dart';
import '../services/session_refresh_mixin.dart';
import '../ui/components/controls.dart';
import '../utils/error_utils.dart';
import '../utils/money.dart';
import '../utils/units.dart';
import '../widgets/variant_catalogue.dart';
import '../widgets/variant_form_sheet.dart';
import '../routing/home_shell.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import 'package:image_picker/image_picker.dart';
import '../services/product_image_store.dart';
import '../ui/components/product_photo.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({this.focusedProductId, super.key});

  /// A product id from a deep link (`/inventory/product/:productId`).
  ///
  /// Identity comes from the PATH PARAMETER rather than `state.extra`, because
  /// `extra` is `null` on a cold start from a deep link and after process death —
  /// a low-stock link that only works once is worse than no link.
  final String? focusedProductId;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with LiveRefresh<InventoryScreen>, SessionRefresh<InventoryScreen> {
  List<Product> _products = [];

  /// True until the first load resolves, so the list can tell "still loading"
  /// from "nothing here yet" — an empty shop and a loading shop look identical
  /// otherwise, and the empty state would flash at every cold start.
  bool _loading = true;

  /// Which products are sold as variants, and what those variants are.
  ///
  /// Loaded with the products rather than per row: the list needs to know for
  /// every tile whether it has variants to offer, and a query per tile is a
  /// list that stutters on exactly the shops with the most stock.
  VariantCatalogue _variants = VariantCatalogue.empty;

  /// The limit the sheet opens on. Not the source of truth — that is each
  /// product's own `reorderLevel` — just the value the owner last agreed to.
  int _lowStockLimit = 5;

  /// Re-reads on a product or stock change: both are what the list shows.
  @override
  Set<LiveReason> get liveReasons => const <LiveReason>{
        LiveReason.products,
        LiveReason.stock,
      };

  @override
  bool get liveIsVisible => TickerMode.valuesOf(context).enabled;

  @override
  Future<void> reloadFromLive() => _load();

  /// The session that was reading the catalogue has ended: stop showing it
  /// theirs. The list is re-read for whoever signs in next, and the skeleton
  /// — not the "catalogue empty" panel — is what a shop with products and no
  /// session yet must look like.
  @override
  void clearForSession() {
    _loading = true;
    _products = const <Product>[];
    _variants = VariantCatalogue.empty;
  }

  @override
  Future<void> reloadFromSession() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // No clearing of the previous list first: a pull-to-refresh that blanks the
    // screen reads as "my stock is gone" for the second it takes to reload. The
    // RefreshIndicator's own spinner says the reload is happening.
    final p = await DatabaseHelper.instance.getProducts();
    final catalogue = await VariantCatalogue.load();
    final int? limit = p
        .where((Product product) => product.reorderLevel > 0)
        .map((Product product) => product.reorderLevel)
        .fold<int?>(null, (int? common, int level) =>
            common == null || common == level ? level : -1);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _products = p;
      _variants = catalogue;
      // The level the shop actually uses, when every product agrees on one. If
      // they disagree, the dialog starts on the default rather than silently
      // proposing to flatten a per-product choice the owner made on purpose.
      if (limit != null && limit >= 0) _lowStockLimit = limit;
    });
    // Announced rather than merely scrolled: a deep-linked product arriving at the
    // top of a 400-row list is invisible to anyone not watching the screen move,
    // and the whole point of the link is that they end up looking at the product.
    if (widget.focusedProductId != null) {
      // An internal marker, not copy: it never reaches a widget, so it stays a
      // literal. Translating it would be translating the routing contract.
      final match =
          p.where((Product e) => 'id-${e.id}' == widget.focusedProductId);
      if (match.isNotEmpty) {
        await SemanticsService.sendAnnouncement(
          // `View.of(context)` rather than a deprecated global: the announcement
          // is scoped to the window it was requested from, so a second window
          // does not hear the first one's navigation.
          View.of(context),
          '${match.first.name} is in the inventory list',
          Directionality.of(context),
        );
      }
    }
  }

  Future<void> _openEditor([Product? existing]) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductEditor(existing: existing, onSaved: _load),
    );
  }

  /// Writes one audit row for an action this screen just took.
  ///
  /// Delegates to [recordActionAudit] so attribution is resolved one way for
  /// the whole app — the screen and the editor sheet both write audit rows, and
  /// two copies of "who is signed in" eventually disagree.
  ///
  /// A failure to write a log row never fails the action itself: a shop that
  /// could not adjust its stock because a log insert failed is worse than a
  /// shop with a gap in its log.
  Future<void> _audit(
    AuditAction action,
    AuditEntity entity, {
    String? entityId,
    String? detail,
  }) =>
      recordActionAudit(
        context.read<AppState>(),
        action: action,
        entity: entity,
        entityId: entityId,
        detail: detail,
      );

  Future<void> _adjustStock(Product p) async {
    // A product sold as variants has no stock count of its own to correct: its
    // `stock_qty` is the sum of its variants (see
    // VariantCatalogue.writeAggregateStock), so adjusting the parent would
    // overwrite that sum with a number nothing derives from. Correct one
    // variant instead, chosen by name.
    if (_variants.sellsAsVariants(p)) {
      await _adjustVariantStock(p);
      return;
    }
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _AdjustDialog(product: p),
    );
    if (result == null) return;
    final delta = int.tryParse(result['delta'] ?? '');
    if (delta == null || delta == 0) return;
    if (!mounted) return;
    final state = context.read<AppState>();
    final staffName = state.currentStaffName!;
    // Shrinkage is reviewed per cashier, and `deleteStaffWithTombstone`
    // anonymises the ledger by `staff_id`. Recording only the display name
    // leaves the removed cashier named on every adjustment they made.
    int? staffId;
    String? staffRemoteId;
    if (!state.isOwnerSession) {
      final staff = await DatabaseHelper.instance.getStaff();
      final match = staff.where((s) => s.name == staffName);
      staffId = match.isEmpty ? null : match.first.id;
      staffRemoteId = match.isEmpty ? null : match.first.remoteId;
    }
    try {
      await DatabaseHelper.instance.adjustStock(
          StockAdjustment(
            productId: p.id!,
            productName: p.name,
            delta: delta,
            reason: result['reason'] ?? '',
            staffName: staffName,
            createdAt: DateTime.now().toIso8601String(),
          ),
          staffId: staffId);
      // The ledger records THAT the stock moved; the audit log records WHO
      // moved it. Both are needed, because the stock adjustment table carries
      // no row for "the owner waived the low-stock warning".
      await _audit(
        AuditAction.stockAdjusted,
        AuditEntity.product,
        entityId: 'id-${p.id}',
        detail: '${delta > 0 ? '+' : ''}$delta'
            '${result['reason']?.isNotEmpty == true ? ' — ${result['reason']}' : ''}',
      );
      await _load();
      // The server owns the authoritative stock count, so the correction has to
      // be pushed as an adjustment rather than folded into the next catalogue
      // sync. Reported, not silent: the local count is already correct, but the
      // shop's other devices will not see this change until it lands.
      if (mounted) {
        final pushed = await BackendService.adjustStockOnBackend(
          product: p,
          delta: delta,
          reason: result['reason'],
          staffProfileId: staffRemoteId,
        );
        if (!pushed && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  AppLocalizations.of(context).inventoryStockSavedLocally)));
        }
      }
    } on StateError catch (error) {
      if (mounted) {
        final message = error.toString().contains('below zero')
            ? AppLocalizations.of(context).inventoryStockCannotGoBelowZero
            : AppLocalizations.of(context).inventoryStockUpdateFailed;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(AppLocalizations.of(context).inventoryAdjustStockFailed)));
      }
    }
  }

  /// Corrects the stock of one variant of a product sold as variants.
  ///
  /// Deliberately not pushed to the backend: the adjustment API takes a product
  /// and adjusts *that* product's count, and this count belongs to a variant.
  /// Pushing it as a product adjustment would move the server's aggregate by a
  /// number that means something different there, so the correction stays on
  /// this till and arrives with the variants themselves once the backend carries
  /// them.
  Future<void> _adjustVariantStock(Product p) async {
    final variants = _variants.of(p);
    if (variants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            AppLocalizations.of(context).inventoryAddVariantsFirst(p.name)),
      ));
      return;
    }
    final chosen = await showDialog<ProductVariant>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Which variant? · ${p.name}'),
        children: [
          for (final variant in variants)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, variant),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  variant.isLow
                      ? Icons.warning_amber_outlined
                      : Icons.label_outline,
                ),
                title: Text(variant.name),
                subtitle: Text(AppLocalizations.of(context)
                    .inventoryStockqtyStock(variant.stockQty)),
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _AdjustDialog(product: p, variant: chosen),
    );
    if (result == null) return;
    final delta = int.tryParse(result['delta'] ?? '');
    if (delta == null || delta == 0) return;
    try {
      await VariantCatalogue.adjustVariantStock(chosen.id!, delta.toDouble());
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('${chosen.label} is now ${chosen.stockQty + delta} in stock.'),
      ));
    } on StateError catch (error) {
      if (!mounted) return;
      // Never match an exception string to decide what to tell the user: the
      // message is thrown by the database layer and a wording change there would
      // silently turn "check the quantity" into a generic failure. `ErrorUtils` is
      // the one boundary that maps a failure to words.
      showAppSnackBar(
        context,
        message: ErrorUtils.userMessage(AppLocalizations.of(context), error),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).inventoryAdjustStockFailed)));
    }
  }

  Future<void> _delete(Product p) async {
    // Captured before the first await: the dialog is built from it, and a
    // BuildContext must not be read after it has been awaited away.
    final AppLocalizations l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.inventoryDeleteTitle),
        content: Text('Remove ${p.name} from inventory?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).inventoryDeleteAction)),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper.instance.deactivateProduct(p.id!);
      // A deactivated product is still in the history — the till's past sales
      // point at it — so the row says deactivated rather than deleted, and
      // carries the name because the id will stop resolving.
      await _audit(
        AuditAction.productUpdated,
        AuditEntity.product,
        entityId: 'id-${p.id}',
        detail: l10n.inventoryDeactivatedProduct(p.name),
      );
      await _load();
    }
  }

  /// Sets the low-stock limit for every active product at once.
  ///
  /// A shop deciding its limit is 8, not 5, is not a decision about 214 products
  /// one at a time. The alternative — an owner who will not tap through the
  /// editor 214 times — is a dashboard warning about nothing, which trains them
  /// to ignore it. The per-product level stays where it already is, for the
  /// handful of items a shop genuinely counts differently.
  Future<void> _setLowStockLimit() async {
    final l10n = AppLocalizations.of(context);
    final int? limit = await showDialog<int>(
      context: context,
      builder: (dialogContext) => _LowStockLimitDialog(
        title: l10n.inventoryLowStockLimitTitle,
        initial: _lowStockLimit,
      ),
    );
    if (limit == null || !mounted) return;
    setState(() => _lowStockLimit = limit);
    final int changed = await DatabaseHelper.instance.setLowStockLimit(limit);
    // One row, not one per product: a limit set across the whole catalogue is
    // one decision, and 214 identical audit rows would bury every other entry.
    await _audit(
      AuditAction.stockAdjusted,
      AuditEntity.product,
      detail: l10n.inventoryLowStockLimitAudit(changed, limit),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l10n.inventoryLowStockLimitApplied(changed, limit)),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = context.watch<AppState>().isOwnerSession;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: l10n.inventoryAddProduct,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _products.isEmpty && _loading
            ? const _InventorySkeleton()
            : ListView.separated(
                itemCount: _products.isEmpty ? 1 : _products.length + 1,
                separatorBuilder: (_, i) => Divider(
                  height: 1,
                  indent: _rowDividerInset(context),
                  color: AppColors.of(context).outline,
                ),
                itemBuilder: (_, i) {
                  // An empty catalogue is a setup problem, not an empty list:
                  // say what is missing and offer the one action that fixes it.
                  if (i == 0 && _products.isEmpty) {
                    return _InventoryEmptyState(onAdd: () => _openEditor());
                  }
                  // Row zero is the shot-cup entry rather than a product: it is a
                  // way of selling what is already in the catalogue, not another
                  // line of it, and burying it under the first hundred sodas is
                  // how a bar never finds the feature that makes it a bar.
                  if (_products.isEmpty || i == 0) {
                    return Column(
                      children: <Widget>[
                        Semantics(
                          label: l10n.inventoryShotCupsSpoken,
                          child: ListTile(
                            leading: const Icon(Icons.local_drink_outlined),
                            title: Text(l10n.inventoryShotCupsTitle),
                            subtitle: Text(l10n.inventoryShotCupsSubtitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push(Routes.shotCups),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.tune),
                          title: Text(l10n.inventoryLowStockLimitTitle),
                          // The CURRENT limit, so a seller opening this sees what
                          // the warning is set to rather than a blank field. A
                          // policy nobody can read is a policy nobody sets.
                          subtitle: Text(l10n.inventoryLowStockLimitSubtitle(
                              _lowStockLimit)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _setLowStockLimit,
                        ),
                      ],
                    );
                  }
                  final p = _products[i - 1];
                  final variantCount = _variants.of(p).length;
                  return Semantics(
                    label: l10n.inventoryNameStock(
                        formatMoney(p.sellPrice), p.name, p.stockQty),
                    child: _ProductListTile(
                      // Stable identity: a filtered or refreshed list reuses the
                      // row's element only when the key says it is the same
                      // product, so state never bleeds between two rows.
                      key: ValueKey('product-${p.id}'),
                      product: p,
                      variantCount: variantCount,
                      tracksVariants: _variants.tracks(p),
                      isOwner: isOwner,
                      onEdit: () => _openEditor(p),
                      onAdjust: () => _adjustStock(p),
                      onDelete: () => _delete(p),
                    ),
                  );
                },
              ),
      ),
    );
  }

  /// Divider inset that lines the rule up with the product name rather than the
  /// screen edge — the badge is the row's anchor, the text is what the rule
  /// separates.
  double _rowDividerInset(BuildContext context) =>
      AppSpacing.of(context).md + 40 + AppSpacing.of(context).md;
}

/// The first load, drawn as the rows it is about to become.
///
/// A skeleton rather than a spinner because the shape tells the shopkeeper what
/// is coming — a list — and nothing moves when the content lands. The shimmer is
/// deliberately absent: a pulsing placeholder on a till used in a bright shop is
/// an animation nobody asked for, and this app's motion budget is spent on
/// things that mean something.
class _InventorySkeleton extends StatelessWidget {
  const _InventorySkeleton();

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppShapes shapes = AppShapes.of(context);

    return Column(
      children: List<Widget>.generate(8, (int i) {
        return Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.md,
            end: spacing.md,
            top: spacing.sm,
            bottom: spacing.sm,
          ),
          child: Row(
            children: <Widget>[
              // The count badge's slot.
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.surfaceSunken,
                  borderRadius: shapes.chipRadius,
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // The name's slot: wider than the meta line's, because
                    // that is the proportion the real rows land at.
                    FractionallySizedBox(
                      widthFactor: i.isEven ? 0.62 : 0.45,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: colors.surfaceSunken,
                          borderRadius: shapes.barRadius,
                        ),
                      ),
                    ),
                    SizedBox(height: spacing.sm),
                    FractionallySizedBox(
                      widthFactor: 0.35,
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors.surfaceSunken,
                          borderRadius: shapes.barRadius,
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

/// A catalogue with nothing in it.
///
/// Three different situations produce an empty-looking list and this is the one
/// that is a setup problem: a loading list gets the skeleton, a filtered list
/// gets its filter cleared, and a genuinely empty catalogue gets this — the
/// words that say what is missing and the one action that fixes it.
class _InventoryEmptyState extends StatelessWidget {
  const _InventoryEmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsets.all(spacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.inventory_2_outlined,
            size: 40,
            color: colors.onSurfaceMuted,
          ),
          SizedBox(height: spacing.lg),
          Text(
            l10n.inventoryEmptyTitle,
            textAlign: TextAlign.center,
            style: type.titleMedium,
          ),
          SizedBox(height: spacing.xs),
          Text(
            l10n.inventoryEmptyBody,
            textAlign: TextAlign.center,
            style: type.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
          ),
          SizedBox(height: spacing.lg),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(l10n.inventoryAddProduct),
          ),
        ],
      ),
    );
  }
}

/// A product list tile with reliable edit/adjust/delete actions.
///
/// Uses an explicit menu button instead of PopupMenuButton to avoid
/// touch target issues in ListView.
class _ProductListTile extends StatelessWidget {
  const _ProductListTile({
    required this.product,
    required this.variantCount,
    required this.tracksVariants,
    required this.isOwner,
    required this.onEdit,
    required this.onAdjust,
    required this.onDelete,
    super.key,
  });

  final Product product;
  final int variantCount;
  final bool tracksVariants;
  final bool isOwner;
  final VoidCallback onEdit;
  final VoidCallback onAdjust;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    final bool isOut = product.stockQty <= 0;
    final bool isLow = !isOut && product.isLow;

    // The state, resolved ONCE from the value. Normal is quiet on purpose: a
    // till where every in-stock product wears a green chip is a till where the
    // amber ones no longer stand out.
    final StatusTone tone = isOut
        ? StatusTone.danger
        : isLow
            ? StatusTone.warning
            : StatusTone.neutral;

    // One line, three facts, in the order a shopkeeper scans them. The count is
    // deliberately NOT repeated here — the badge on the leading edge is the
    // count, and saying it twice makes both harder to read.
    final String meta = [
      product.category,
      formatMoney(product.sellPrice),
      if (tracksVariants && variantCount == 0) l10n.inventoryNoVariantsYet,
      if (variantCount > 0) l10n.sellVariantCount(variantCount),
    ].join(' · ');

    return Semantics(
      button: true,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.md,
            end: spacing.xs,
            top: spacing.sm,
            bottom: spacing.sm,
          ),
          child: ConstrainedBox(
            // The floor is on the ROW, not the text: a 44px minimum with the
            // name free to wrap keeps the target legal at any text scale.
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                _StockCountBadge(
                  quantity: product.stockQty.round(),
                  tone: tone,
                ),
                SizedBox(width: spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        product.name,
                        // Two lines, then an ellipsis.
                        //
                        // The comment here said "no ellipsis: a cut-off product
                        // name is a product nobody can find" — but `maxLines`
                        // WITHOUT `overflow` means `TextPainter` never renders
                        // lines past the limit, so a third line was dropped
                        // with no marker at all and an unbroken word longer
                        // than the row was chopped by the row's edge.
                        //
                        // The row's `Semantics` label carries the full name, so
                        // this is a visual budget rather than a truncation of
                        // the data.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.titleSmall,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        meta,
                        style: type.bodySmall?.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                      if (isOut || isLow) ...[
                        SizedBox(height: spacing.xs),
                        StatusChip(
                          tone: tone,
                          text: isOut
                              ? l10n.inventoryOutOfStock
                              : l10n.inventoryLowStock,
                        ),
                      ],
                    ],
                  ),
                ),
                _ProductActionMenu(
                  isOwner: isOwner,
                  onEdit: onEdit,
                  onAdjust: onAdjust,
                  onDelete: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductActionMenu extends StatelessWidget {
  const _ProductActionMenu({
    required this.isOwner,
    required this.onEdit,
    required this.onAdjust,
    required this.onDelete,
  });

  final bool isOwner;
  final VoidCallback onEdit;
  final VoidCallback onAdjust;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    return PopupMenuButton<String>(
      tooltip: l10n.inventoryActionsTooltip,
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
            break;
          case 'adjust':
            onAdjust();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20),
              SizedBox(width: 12),
              Text(l10n.inventoryEditAction),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'adjust',
          child: Row(
            children: [
              Icon(Icons.inventory_outlined, size: 20),
              SizedBox(width: 12),
              Text(l10n.inventoryAdjustAction),
            ],
          ),
        ),
        if (isOwner)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 20, color: colors.danger),
                SizedBox(width: 12),
                Text(
                  l10n.inventoryDeleteAction,
                  style: TextStyle(color: colors.danger),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The photograph controls for one product.
///
/// Its own widget rather than inline in the editor's `build` because it holds
/// three pieces of local presentation state — what is stored, what was picked,
/// what is marked for removal — and the editor already has six of those for its
/// own fields. Keeping them in one place means the "removed" state cannot
/// disagree with the preview.
class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.existingPath,
    required this.picked,
    required this.removed,
    required this.importing,
    required this.onPick,
    required this.onRemove,
    required this.onUndoRemove,
  });

  /// The path already stored on the product, if it has one.
  final String? existingPath;

  /// A file picked in this session, not yet imported.
  final File? picked;

  /// Whether the stored photograph is marked for removal.
  final bool removed;

  final bool importing;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final VoidCallback onUndoRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spacing = AppSpacing.of(context);
    final type = AppTypography.of(context);
    final colors = AppColors.of(context);

    // One preview resolves in priority order: a pick wins over a removal wins
    // over what is already stored. A preview that showed the stored photo while
    // "remove" was pending would be a preview of the wrong thing.
    if (picked != null) {
      return Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              picked!,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            child: Text(
              l10n.inventoryPhotoHelp,
              style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
            ),
          ),
          IconButton(
            onPressed: importing ? null : onPick,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.inventoryPhotoChange,
          ),
        ],
      );
    }

    if (removed) {
      return Row(
        children: <Widget>[
          Icon(Icons.image_not_supported_outlined,
              size: 72, color: colors.onSurfaceMuted),
          SizedBox(width: spacing.md),
          Expanded(
            child: Text(
              l10n.inventoryPhotoRemovedNote,
              style: type.bodySmall,
            ),
          ),
          TextButton(
            onPressed: importing ? null : onUndoRemove,
            child: Text(l10n.actionUndo),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (existingPath != null) ...<Widget>[
          ProductPhoto(imagePath: existingPath, size: 72),
          SizedBox(width: spacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(l10n.inventoryPhotoSection, style: type.titleSmall),
              SizedBox(height: 2),
              Text(
                l10n.inventoryPhotoHelp,
                style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
              ),
            ],
          ),
        ),
        if (existingPath != null)
          IconButton(
            onPressed: importing ? null : onRemove,
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.inventoryPhotoRemove,
            color: colors.danger,
          )
        else
          TextButton.icon(
            onPressed: importing ? null : onPick,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(l10n.inventoryPhotoAdd),
          ),
      ],
    );
  }
}

class _ProductEditor extends StatefulWidget {
  final Product? existing;
  final VoidCallback onSaved;
  const _ProductEditor({this.existing, required this.onSaved});
  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  late final TextEditingController _name,
      _category,
      _cost,
      _price,
      _stock,
      _reorder,
      _stamp,
      _bottleMl,
      _halfPrice,
      _quarterPrice,
      _barcode;
  String? _error;

  /// Codes already attached to this product, at both levels.
  ///
  /// A list rather than one field, because a product routinely answers to more
  /// than one: the supplier's EAN, a second distributor's, a code the owner
  /// assigned, and a code per variant. Barcodes are written through the barcode
  /// API rather than `upsertProduct`, which rewrites the whole product row and
  /// would erase them on the next unrelated save.
  ///
  /// Each row carries the level it resolves at, because a code on the product
  /// and a code on one of its variants behave differently at the till and the
  /// owner has to be able to tell which is which.
  List<ProductCode> _codes = [];

  /// Variants being edited in this dialog session, staged rather than written.
  ///
  /// `product_variants.product_id` is NOT NULL, so a variant cannot be saved
  /// before the product row exists — and a variant the owner has typed but not
  /// finished should not be in the catalogue at all if they then back out.
  List<VariantDraft> _drafts = [];

  /// Variants already in the table that this session removes. Applied after the
  /// product save, so backing out of the sheet undoes the removal too.
  final List<int> _removedVariantIds = [];

  /// The rows behind [_removedVariantIds], so the save can name what was
  /// removed rather than only that something was.
  final List<VariantDraft> _removedVariantDrafts = [];

  /// Whether the product is sold as variants. Read from the row rather than
  /// from the passed-in [Product], because `Product.fromMap` does not populate
  /// it — a product that *is* sold as variants arrives here looking like one
  /// that is not, and saving it would quietly turn the feature off.
  bool _trackVariants = false;

  /// What the product is measured in, for the same reason as [_trackVariants].
  ProductUnit _unit = ProductUnit.each;

  /// Covers the codes, the variants and the two flag columns, which arrive in
  /// three separate reads.
  bool _loadingMeta = true;

  /// Volume sizes this shop has used before, most-used first.
  ///
  /// Offered as one-tap chips under the keg/tank size field. A bar selling
  /// Tusker, a keg of.proto and a 50-litre tank types three different five-digit
  /// numbers that are all the same shop remembering its own stock, and the chips
  /// turn three remembered numbers into one remembered list.
  ///
  /// Read shop-wide rather than per product: a keg size is not a property of one
  /// product, and the product being typed may not have a row yet.
  List<CupSizeSuggestion> _sizeSuggestions = const [];

  /// How many chips to offer before the row stops being scannable.
  static const _maxSizeSuggestions = 6;

  /// The photograph picked in this session, not yet imported.
  ///
  /// A file, not a path already in the store: the store names its files by
  /// product id, and a NEW product has no id until it is saved. So the pick is
  /// held and flushed AFTER the insert — the same order the variants follow.
  /// Importing before the insert would have nowhere to put the file.
  File? _pickedPhoto;

  /// Whether the existing photograph is marked for removal on save.
  ///
  /// Deferred rather than immediate so backing out of the sheet without saving
  /// leaves the photograph alone, exactly as it leaves an un-saved variant.
  bool _photoRemoved = false;

  /// True while a photograph is being imported.
  final bool _importingPhoto = false;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _cost.dispose();
    _price.dispose();
    _stock.dispose();
    _reorder.dispose();
    _stamp.dispose();
    _bottleMl.dispose();
    _halfPrice.dispose();
    _quarterPrice.dispose();
    _barcode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _category = TextEditingController(text: e?.category ?? '');
    // Seeded through an explicit formatter, never `toString()`.
    //
    // `Money.toString()` returns `Money(50000 minor units)` — the debug
    // representation, in cents. Putting that in a field and then parsing it
    // back failed, so every price was both unreadable and unsaveable, and an
    // optional price read as "unparseable" was silently written back as NULL.
    // A helper here means the correct conversion cannot be forgotten in one
    // field out of seven.
    _cost = TextEditingController(text: _editAmount(e?.costPrice));
    _price = TextEditingController(text: _editAmount(e?.sellPrice));
    _stock = TextEditingController(text: _editQuantity(e?.stockQty));
    _reorder = TextEditingController(text: e?.reorderLevel.toString() ?? '5');
    _stamp = TextEditingController(text: e?.exciseStampBatch ?? '');
    _bottleMl = TextEditingController(text: e?.bottleMl.toString() ?? '750');
    _halfPrice = TextEditingController(text: _editAmount(e?.halfPrice));
    _quarterPrice = TextEditingController(text: _editAmount(e?.quarterPrice));
    _barcode = TextEditingController();
    _loadMeta();
    _loadSizeSuggestions();
  }

  Future<void> _loadSizeSuggestions() async {
    final loaded = await DatabaseHelper.instance.getCupSizeSuggestions();
    if (!mounted) return;
    setState(() => _sizeSuggestions = loaded);
  }

  /// The chips worth offering under the size field.
  ///
  /// Hidden for a countable product: "750 ml" next to a thing with no size is
  /// a question nobody asked, and a countable product's field is a legacy
  /// leftover that is ignored on save.
  List<CupSizeSuggestion> get _visibleSizeSuggestions =>
      _unit == ProductUnit.each ? const [] : _sizeSuggestions;

  Widget _sizeSuggestionChips() => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Semantics(
          container: true,
          label: AppLocalizations.of(context).inventorySizeSuggestionsSpoken,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in _visibleSizeSuggestions.take(_maxSizeSuggestions))
                ActionChip(
                  label: Text(Volume(s.sizeMl.toDouble()).display),
                  onPressed: () => _bottleMl.text = s.sizeMl.toString(),
                ),
            ],
          ),
        ),
      );

  /// Reads everything about an existing product that the product row alone
  /// cannot tell us: its variants, its codes at both levels, and the two
  /// columns `Product.fromMap` leaves at their defaults.
  Future<void> _loadMeta() async {
    final existing = widget.existing;
    if (existing?.id == null) {
      if (mounted) setState(() => _loadingMeta = false);
      return;
    }
    final productId = existing!.id!;
    final db = DatabaseHelper.instance;
    final flags = await VariantCatalogue.productFlags(productId);
    final variants = await db.getVariants(productId, activeOnly: false);
    final codes = await VariantCatalogue.codesForProduct(productId);
    if (!mounted) return;
    String storedCodeFor(int? variantId) => codes
        .firstWhere(
          (code) => code.variantId == variantId,
          orElse: () => const ProductCode(barcode: ''),
        )
        .barcode;
    setState(() {
      _unit = flags.unit;
      // Variants that exist are treated as "sold as variants" even when the flag
      // was never set: turning the flag off here would hide variants the owner
      // can see, and would leave them unsellable at the till.
      _trackVariants = flags.trackVariants || variants.isNotEmpty;
      _drafts = [
        for (final variant in variants)
          VariantDraft.fromVariant(variant,
              storedBarcode: storedCodeFor(variant.id)),
      ];
      _codes = codes;
      _loadingMeta = false;
    });
  }

  /// Turns "sold as variants" on or off.
  ///
  /// On: the stock field becomes the variants' total (kept in sync on save), and
  /// the variant list appears. Off: the stock field goes back to being this
  /// product's own count. Any variants already added stay where they are — they
  /// are the owner's data, and hiding them would look like losing them.
  void _setTrackVariants(bool value) {
    setState(() {
      _trackVariants = value;
      if (value && _stock.text.trim().isEmpty) {
        final total = _drafts.fold<double>(0, (sum, d) => sum + d.stockQty);
        _stock.text = _editQuantity(total);
      }
    });
  }

  /// A money value as editable whole shillings, or empty when absent.
  ///
  /// Whole shillings rather than two decimals because that is what these fields
  /// have always accepted and what a Kenyan shopkeeper types. The internal
  /// representation stays integer cents; this is purely the display edge.
  static String _editAmount(Money? value) {
    if (value == null) return '';
    final major = value.minorUnits ~/ kMinorUnitsPerMajor;
    final cents = value.minorUnits % kMinorUnitsPerMajor;
    // Show cents only when they exist, so a whole-shilling price does not read
    // Not `formatMoney`: this is an EDIT field, and it has to show `500` rather
    // than `KSh 500.00` — a figure the owner types back into their own price list
    // should not arrive with a currency symbol glued to it. Not an ARB key
    // either: the digits come from arithmetic, not a translator, and a message
    // that only places a bare number is a number no locale can reformat.
    // as "500.00" while the shop's price list says "500".
    return cents == 0 ? '$major' : '$major.${cents.toString().padLeft(2, '0')}';
  }

  /// A stock quantity for editing: no trailing `.0` for a whole number.
  static String _editQuantity(double? value) {
    if (value == null) return '';
    return value % 1 == 0 ? value.toInt().toString() : value.toString();
  }

  Future<void> _reloadCodes() async {
    final existing = widget.existing;
    if (existing?.id == null) return;
    final codes = await VariantCatalogue.codesForProduct(existing!.id!);
    if (!mounted) return;
    setState(() => _codes = codes);
  }

  Future<void> _addBarcode() async {
    final raw = _barcode.text.trim();
    final code = Barcode.normalise(raw);
    final problem = Barcode.rejectionReason(code);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    // The product has to exist before a barcode can point at it, so an
    // unsaved new product gets its codes after the save rather than before.
    final existing = widget.existing;
    if (existing?.id == null) {
      setState(() =>
          _error = AppLocalizations.of(context).inventorySaveBeforeBarcode);
      return;
    }
    final added = await DatabaseHelper.instance.addBarcode(
      productId: existing!.id!,
      barcode: code,
      kind: BarcodeKind.supplier,
    );
    if (!mounted) return;
    if (!added) {
      // `barcode TEXT PRIMARY KEY` makes the duplicate impossible rather than
      // merely discouraged, so this is the one place a duplicate can surface —
      // and it names the product that already owns the code, which tells the
      // owner which product to remove it from.
      final owner = await DatabaseHelper.instance.getProductOwningBarcode(code);
      if (!mounted) return;
      setState(() => _error = owner == null
          ? AppLocalizations.of(context).inventoryBarcodeOnOtherProduct
          : AppLocalizations.of(context).inventoryBarcodeAlready(owner.name));
      return;
    }
    _barcode.clear();
    setState(() => _error = null);
    await _reloadCodes();
  }

  Future<void> _removeBarcode(ProductCode code) async {
    // Captured before the first await: holding a BuildContext across one is
    // exactly what `use_build_context_synchronously` forbids.
    final AppState state = context.read<AppState>();
    final l10n = AppLocalizations.of(context);
    await DatabaseHelper.instance.removeBarcode(code.barcode);
    // A barcode removed is a code someone at the till can no longer scan, so
    // the audit row says which product it belonged to — the code itself is the
    // thing that just stopped working.
    await recordActionAudit(
      state,
      action: AuditAction.barcodeRemoved,
      entity: AuditEntity.barcode,
      entityId: code.barcode,
      detail:
          code.isVariantLevel ? code.variantName : l10n.variantAllSizesLabel,
    );
    if (!mounted) return;
    setState(() => _error = null);
    await _reloadCodes();
  }

  /// Changes what a code is labelled as. Informational only, but a distributor
  /// code labelled "own" is the kind of thing that makes an import's duplicate
  /// report unreadable three months later.
  Future<void> _cycleBarcodeKind(ProductCode code) async {
    final AppState state = context.read<AppState>();
    final index = BarcodeKind.kinds.indexOf(code.kind);
    final next = BarcodeKind.kinds[(index + 1) % BarcodeKind.kinds.length];
    await DatabaseHelper.instance.setBarcodeKind(code.barcode, next);
    await recordActionAudit(
      state,
      action: AuditAction.barcodeKindChanged,
      entity: AuditEntity.barcode,
      entityId: code.barcode,
      detail: '${BarcodeKind.label(code.kind)} → ${BarcodeKind.label(next)}',
    );
    if (!mounted) return;
    await _reloadCodes();
  }

  // ---------------- Variants ----------------

  /// The parent as the form currently has it, for seeding a new variant.
  ///
  /// Read from the *fields* rather than from the stored product, so a variant
  /// added after the owner has just corrected the price inherits the price they
  /// are looking at. Every field falls back to the stored value rather than
  /// failing, because seeding is a convenience and must never be the reason a
  /// variant cannot be added.
  Product _draftParent() {
    final existing = widget.existing;
    double number(String text, double fallback) =>
        double.tryParse(text.trim()) ?? fallback;
    return Product(
      id: existing?.id,
      name: _name.text.trim().isEmpty
          ? (existing?.name ??
              AppLocalizations.of(context).inventoryThisProduct)
          : _name.text.trim(),
      category: _category.text.trim().isEmpty
          ? AppLocalizations.of(context).inventoryDefaultCategory
          : _category.text.trim(),
      costPrice:
          Money.fromMajor(number(_cost.text, existing?.costPrice.asMajor ?? 0)),
      sellPrice: Money.fromMajor(
          number(_price.text, existing?.sellPrice.asMajor ?? 0)),
      stockQty: number(_stock.text, existing?.stockQty ?? 0),
      reorderLevel:
          int.tryParse(_reorder.text.trim()) ?? existing?.reorderLevel ?? 0,
      bottleMl:
          int.tryParse(_bottleMl.text.trim()) ?? existing?.bottleMl ?? 750,
      unit: _unit,
      trackVariants: _trackVariants,
      active: existing?.active ?? true,
      updatedAt: DateTime.now().toIso8601String(),
      remoteId: existing?.remoteId,
    );
  }

  /// Imports, or removes, the photograph for [productId].
  ///
  /// Called after the product row is durable, so the id exists and the store
  /// has a filename. A failure is REPORTED rather than propagated: the product
  /// the owner just saved must not be rolled back because a photograph failed.
  Future<void> _flushPhoto(int productId, AppState state) async {
    final source = _pickedPhoto;
    final removed = _photoRemoved;
    if (source == null && !removed) return;

    final l10n = AppLocalizations.of(context);
    try {
      if (removed) {
        await ProductImageStore.delete(productId);
        await DatabaseHelper.instance.setProductImage(null, productId);
      } else {
        final relative = await ProductImageStore.save(
          source!,
          productId: productId,
        );
        await DatabaseHelper.instance.setProductImage(relative, productId);
      }
      await recordActionAudit(
        state,
        action: removed
            ? AuditAction.productPhotoRemoved
            : AuditAction.productPhotoSet,
        entity: AuditEntity.product,
        entityId: 'id-$productId',
        detail: widget.existing?.name ?? l10n.inventoryThisProduct,
      );
    } on ProductImageException {
      // Kept as a message rather than a throw: the product is saved and the
      // catalogue is correct, and losing the whole save over a photograph
      // would be the worse outcome.
      if (!mounted) return;
      // The message names the phone's storage rather than "something went
      // wrong", because the two failures that happen are a full disk and a
      // file the gallery moved — and the owner can act on the first.
      setState(() {
        _error = source == null
            ? l10n.inventoryPhotoRemoveFailed
            : l10n.inventoryPhotoAddFailed;
      });
    } finally {
      // Cleared either way, so a retry that fails is not retried by the next
      // save with the same stale pick.
      if (mounted) {
        setState(() {
          _pickedPhoto = null;
          _photoRemoved = false;
        });
      }
    }
  }

  /// Offers the gallery or the camera for a product photograph.
  Future<void> _pickPhoto() async {
    if (_importingPhoto) return;
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.inventoryPhotoFromGallery),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.inventoryPhotoFromCamera),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;

    final XFile? file = await ImagePicker()
        .pickImage(source: picked, maxWidth: 1024, imageQuality: 90);
    if (file == null) return;
    if (!mounted) return;
    setState(() {
      _pickedPhoto = File(file.path);
      _photoRemoved = false;
    });
  }

  Future<void> _addVariant() async {
    final draft = await showVariantFormSheet(
      context,
      seed: VariantDraft.seededFrom(
        parent: _draftParent(),
        parentUnit: _unit,
        position: _drafts.length,
      ),
      // Null while the product itself is still an unsaved draft, in which case
      // the sheet offers the shop-wide cup sizes instead of this product's.
      parentProductId: widget.existing?.id,
    );
    if (draft == null || !mounted) return;
    setState(() => _drafts.add(draft));
  }

  Future<void> _editVariant(int index) async {
    final existingDraft = _drafts[index];
    final draft = await showVariantFormSheet(
      context,
      seed: existingDraft,
      title: AppLocalizations.of(context).inventoryEdit(existingDraft.name),
      parentProductId: widget.existing?.id,
    );
    if (draft == null || !mounted) return;
    setState(() => _drafts[index] = draft);
  }

  /// Stages a variant's removal, after asking.
  ///
  /// Asked, always, even for a variant that has never been written: a variant
  /// holding the only barcode a supplier's label carries, removed by a
  /// mis-tap, stops that label resolving at the till with nothing on screen to
  /// say why.
  Future<void> _removeVariant(int index) async {
    final draft = _drafts[index];
    if (!draft.isNew) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Remove ${draft.name}?'),
          content: Text(draft.hasStoredBarcode
              ? AppLocalizations.of(context).inventoryRemoveVariantBarcodeFreed
              : AppLocalizations.of(context)
                  .inventoryRemoveVariantStopsSelling),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(AppLocalizations.of(context).inventoryRemoveAction),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    setState(() {
      if (draft.id != null) {
        _removedVariantIds.add(draft.id!);
        // Kept alongside the id so the save can log WHICH variant went, not
        // just that one did — a variant id alone is meaningless to anyone
        // reading the log later.
        _removedVariantDrafts.add(draft);
        // The code goes with the variant, so the list must stop showing it
        // before the save that actually frees it.
        _codes = _codes.where((code) => code.variantId != draft.id).toList();
      }
      _drafts.removeAt(index);
      for (var i = 0; i < _drafts.length; i++) {
        _drafts[i] = _drafts[i].copyWith(position: i);
      }
    });
  }

  /// One row in the variant list.
  ///
  /// Shows the four things that tell two variants apart: what it is called, how
  /// big it is, what it costs and how many are left. Swipe removes it, the menu
  /// does the same thing for anyone who cannot swipe, and both go through the
  /// same confirmation.
  Widget _variantRow(int index) {
    final draft = _drafts[index];
    final low = draft.stockQty <= draft.reorderLevel;
    return Dismissible(
      // Keyed by identity, not by position: a `ValueKey` on the index would
      // make a removed row animate out of the wrong place once the list closes
      // the gap.
      key: ValueKey(
          'variant-${draft.id ?? 'new-${draft.name}-${draft.position}'}'),
      direction: DismissDirection.endToStart,
      background: Container(
        // Directional: the delete affordance sits on the trailing edge, which is
        // the LEFT edge under RTL. A physical `right` would put the trash icon
        // under the thumb of an RTL-swiping user.
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 20),
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Icon(Icons.delete_outline),
      ),
      // The row is removed by the callback above, not by the dismiss itself, so
      // returning false keeps `Dismissible` from also trying to remove a widget
      // that is no longer in the list.
      confirmDismiss: (_) async {
        await _removeVariant(index);
        return false;
      },
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: _StockCountBadge(
          quantity: draft.stockQty.round(),
          tone: low ? StatusTone.warning : StatusTone.neutral,
        ),
        title: Text(draft.name.trim().isEmpty
            ? AppLocalizations.of(context).inventoryNewVariantName
            : draft.name),
        subtitle: Text([
          // Blank for a countable variant: it has no size, and printing "0 ml"
          // would invent one.
          if (draft.sizeLabel.isNotEmpty) draft.sizeLabel,
          formatMoney(draft.sellPrice),
          low
              ? AppLocalizations.of(context).inventoryLowStock
              : '${editVariantQuantity(draft.stockQty)} in stock',
        ].join(' · ')),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') _editVariant(index);
            if (value == 'remove') _removeVariant(index);
          },
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            PopupMenuItem(
              value: 'edit',
              child: Text(AppLocalizations.of(context).inventoryEditAction),
            ),
            PopupMenuItem(
              value: 'remove',
              child: Text(AppLocalizations.of(context).inventoryRemoveAction),
            ),
          ],
        ),
        onTap: () => _editVariant(index),
      ),
    );
  }

  /// Writes the staged variants, in the same dialog session as the product.
  ///
  /// Removals first, so a barcode freed by a removed variant can be taken by one
  /// added in the same save, and so the aggregate is computed from what is
  /// actually left. Barcodes are written after their variant exists, because the
  /// code points at the variant's row.
  ///
  /// All deletes + upserts are batched in one transaction (a single fsync for
  /// N variants) rather than N separate transactions.
  Future<void> _saveVariants(int productId) async {
    final AppState state = context.read<AppState>();
    final db = DatabaseHelper.instance;
    final l10n = AppLocalizations.of(context);
    final rawDb = await db.database;
    final savedIds = <int>[];
    await rawDb.transaction((txn) async {
      for (final removedId in _removedVariantIds) {
        // Also frees that variant's barcodes.
        await db.deleteVariantInTransaction(txn, removedId);
      }
      for (var i = 0; i < _drafts.length; i++) {
        final draft = _drafts[i];
        // Position follows the order on screen, so reordering is reordering and
        // the till offers Dark before Regular because the owner put it there.
        final variantId = await db.upsertVariantInTransaction(
            txn, draft.copyWith(position: i).toVariant(productId));
        savedIds.add(variantId);
      }
    });
    // Variants are logged after the transaction that committed them, and the
    // row says which product — a variant id on its own means nothing to anyone
    // reading the log six months later. Every row this gesture produces is
    // written in ONE transaction, so saving a variant list costs one disk
    // commit rather than four to eight.
    final List<AuditLogEntry> auditRows = <AuditLogEntry>[];
    for (final VariantDraft removed in _removedVariantDrafts) {
      auditRows.add(
        recordAuditEntry(
          state,
          action: AuditAction.productVariantRemoved,
          entity: AuditEntity.variant,
          entityId: 'id-$productId',
          detail: removed.name,
        ),
      );
    }
    for (var i = 0; i < _drafts.length; i++) {
      final draft = _drafts[i];
      final variantId = savedIds[i];
      final code = draft.barcode.trim();
      if (code.isNotEmpty && (draft.isNew || draft.barcodeChanged)) {
        auditRows.add(
          recordAuditEntry(
            state,
            action: AuditAction.barcodeAdded,
            entity: AuditEntity.barcode,
            entityId: code,
            detail: 'variant ${draft.name}',
          ),
        );
      }
      if (draft.hasStoredBarcode && draft.barcodeChanged) {
        // A non-nullable String with an empty default, so the `?? ''` the
        // analyzer flagged as a dead null-aware is simply not needed.
        auditRows.add(
          recordAuditEntry(
            state,
            action: AuditAction.barcodeRemoved,
            entity: AuditEntity.barcode,
            entityId: draft.storedBarcode,
            detail: 'variant ${draft.name}',
          ),
        );
      }
      if (draft.isNew) {
        auditRows.add(
          recordAuditEntry(
            state,
            action: AuditAction.productVariantAdded,
            entity: AuditEntity.variant,
            entityId: 'id-$variantId',
            detail: draft.name,
          ),
        );
      } else if (draft.barcodeChanged || draft.name.trim().isNotEmpty) {
        // An existing variant was edited. There is no dirty-tracking on the
        // draft, so this is deliberately broad: "an existing variant was saved"
        // is still a fact worth having, and a row that over-reports is less
        // harmful than a log that says nothing happened when it did.
        auditRows.add(
          recordAuditEntry(
            state,
            action: AuditAction.productVariantUpdated,
            entity: AuditEntity.variant,
            entityId: 'id-$variantId',
            detail: draft.name,
          ),
        );
      }
    }
    await DatabaseHelper.instance.recordAudits(auditRows);
    for (var i = 0; i < _drafts.length; i++) {
      final draft = _drafts[i];
      final variantId = savedIds[i];
      final code = draft.barcode.trim();
      if (draft.hasStoredBarcode && draft.barcodeChanged) {
        await db.removeBarcode(draft.storedBarcode);
      }
      // Only write a code when there is a new one to write: an unchanged code is
      // already in the table, and re-inserting it would fail as a duplicate of
      // itself and take the whole save down with it.
      if (code.isNotEmpty && (draft.isNew || draft.barcodeChanged)) {
        final added = await VariantCatalogue.addVariantCode(
          productId: productId,
          variantId: variantId,
          barcode: code,
        );
        if (!added) {
          // Same constraint as a product-level code: one code resolves to
          // exactly one thing, so a clash is reported rather than resolved.
          final owner = await db.getProductOwningBarcode(code);
          throw StateError(owner == null
              ? l10n.inventoryBarcodeAlreadyUsedAnother(code)
              : l10n.inventoryBarcodeAlready2(code, owner.name));
        }
      }
    }
    if (_trackVariants) {
      // A product sold as variants has no stock count of its own; the parent's
      // row carries the total the ledger checks.
      await VariantCatalogue.writeAggregateStock(productId);
    }
  }

  /// Remembers the size the owner just used, so the chips above the field
  /// improve the next time they are opened.
  ///
  /// Recorded shop-wide rather than against this product: a keg size is a fact
  /// about the shop's bottles, not about one line of the catalogue, and a shop
  /// that pours the same tank behind two different drinks should see the size
  /// offered for both.
  ///
  /// Failures here are swallowed deliberately. The size is already written to
  /// the product row, which is what the till sells; losing a suggestion is not
  /// worth failing a save the owner can see succeed.
  Future<void> _rememberSize(int sizeMl) async {
    if (sizeMl <= 0) return;
    try {
      await DatabaseHelper.instance.upsertCupSizeSuggestion(sizeMl: sizeMl);
    } catch (_) {
      // Intentionally ignored — see above.
    }
  }

  /// Reads an optional price field.
  ///
  /// The distinction that matters here is **empty** versus **unparseable**, and
  /// conflating them is how prices silently disappeared.
  ///
  /// `double.tryParse` returns null for both. Treating a non-numeric entry as
  /// "not set" meant that a field which failed to parse — which happened to
  /// every existing product, because the field was seeded with `Money.toString()`
  /// — was written back as NULL. Merely opening a product and saving an
  /// unrelated field therefore erased its half and quarter prices, with no
  /// error anywhere. An unparseable value is now an error the owner can see; only
  /// a genuinely empty field means "this product is not sold in portions".
  Money? _optionalPrice(TextEditingController controller, String label) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null) {
      throw FormatException(
          AppLocalizations.of(context).inventoryLabelMustNumberEmpty(label));
    }
    if (!Money.isValidMajor(parsed)) {
      throw FormatException(
          AppLocalizations.of(context).inventoryLabelMust0(label));
    }
    return Money.fromMajor(parsed);
  }

  Future<void> _save() async {
    // The session and the catalogue are both read before the first await: the
    // audit rows written after each write are attributed from `state`, and a
    // BuildContext must not be held across one.
    final AppState state = context.read<AppState>();
    final name = _name.text.trim();
    final category = _category.text.trim().isEmpty
        ? AppLocalizations.of(context).inventoryDefaultCategory
        : _category.text.trim();

    // Half and quarter are read first and separately: they are optional, and
    // an optional field needs its own error message. Letting them fall through
    // to the shared validator made an optional field report a required field's
    // problem.
    Money? halfPrice;
    Money? quarterPrice;
    try {
      halfPrice = _optionalPrice(
          _halfPrice, AppLocalizations.of(context).inventoryFieldHalfPrice);
      quarterPrice = _optionalPrice(_quarterPrice,
          AppLocalizations.of(context).inventoryFieldQuarterPrice);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }

    final cost = double.tryParse(_cost.text.trim());
    final price = double.tryParse(_price.text.trim());
    final stock = double.tryParse(_stock.text.trim());
    final reorder = int.tryParse(_reorder.text.trim());
    final bottleMl = int.tryParse(_bottleMl.text.trim());

    if (cost == null || price == null || stock == null) {
      setState(() => _error = cost == null
          ? 'Cost price must be a number'
          : price == null
              ? 'Sell price must be a number'
              : 'Stock must be a number');
      return;
    }

    // Single shared rule set, identical to the Excel and Sheets importers, so
    // the editor cannot persist a row the app's own backup format rejects.
    final problem = Product.validate(
      name: name,
      category: category,
      costPrice: cost,
      sellPrice: price,
      stockQty: stock,
      reorderLevel: reorder ?? -1,
      bottleMl: bottleMl ?? 0,
      halfPrice: halfPrice?.asMajor,
      quarterPrice: quarterPrice?.asMajor,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (price < cost) {
      final proceed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
                title:
                    Text(AppLocalizations.of(context).inventoryLowPriceTitle),
                content: Text(
                    '$name would sell at a loss (KSh $price vs cost KSh $cost). Save anyway?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child:
                          Text(AppLocalizations.of(context).inventoryGoBack)),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                          AppLocalizations.of(context).inventorySaveAnyway)),
                ],
              ));
      if (proceed != true) return;
    }

    // A variant with no name cannot be sold, priced or scanned, and one that
    // slipped through the form's validation would sit in the catalogue as a row
    // nobody can choose at the till.
    final unnamed = _drafts.indexWhere((draft) => draft.name.trim().isEmpty);
    if (unnamed >= 0) {
      setState(() => _error =
          'Give every variant a name — one of them has none (position ${unnamed + 1}).');
      return;
    }

    setState(() => _error = null);
    final product = Product(
      id: widget.existing?.id,
      name: name,
      category: category,
      // Prices arrive from text fields, so they are whole shillings typed by a
      // human and are quantised once here.
      costPrice: Money.fromMajor(cost),
      sellPrice: Money.fromMajor(price),
      stockQty: stock,
      reorderLevel: reorder ?? 0,
      bottleMl: bottleMl ?? 750,
      // Both read from the row rather than from the passed-in product, because
      // `Product.fromMap` leaves them at their defaults — writing them from a
      // product that came out of the database would switch off "sold as
      // variants" and reset the unit on every unrelated edit.
      unit: _unit,
      trackVariants: _trackVariants,
      // Already `Money`, so they pass straight through. Re-quantising here
      // would be the third conversion on the same value.
      halfPrice: halfPrice,
      quarterPrice: quarterPrice,
      exciseStampBatch: _stamp.text.trim(),
      active: widget.existing?.active ?? true,
      updatedAt: DateTime.now().toIso8601String(),
      remoteId: widget.existing?.remoteId,
      // The photograph is flushed after the insert, not here: see
      // [_pickedPhoto]. `imagePath` is only written when it changes, so an
      // unrelated edit never rewrites the column.
      imagePath: widget.existing?.imagePath,
    );
    try {
      // The product first: `product_variants.product_id` is NOT NULL, so a
      // variant has nowhere to point until this row exists.
      final productId = await DatabaseHelper.instance.upsertProduct(product);
      // The product's existence is now durable, so "who changed it" is safe to
      // record: writing the audit row after the write it describes means a
      // crash between the two leaves a product with no audit row, never an
      // audit row for a product that does not exist.
      await recordActionAudit(
        state,
        action: widget.existing == null
            ? AuditAction.productCreated
            : AuditAction.productUpdated,
        entity: AuditEntity.product,
        entityId: 'id-$productId',
        detail: product.trackVariants
            ? '${product.name} · sold as variants'
            : product.name,
      );
      // Then the variants, still inside this same dialog session — the owner
      // configured "Kenyana Beer" and its four variants as one thing, and
      // saving half of it would leave the till offering something the catalogue
      // does not have.
      await _saveVariants(productId);
      await _rememberSize(_unit == ProductUnit.each ? 0 : (bottleMl ?? 0));
      // Then the photograph, now that there is an id to name its file after.
      //
      // Flushed here rather than before the insert because the store names a
      // photograph `<productId>.jpg`, and a new product has no id yet. The
      // order mirrors the variants above for the same reason.
      //
      // A failure here is NOT allowed to lose the product the owner just
      // saved: the catalogue row is already durable, so the import error is
      // recorded and told to them rather than surfaced as a failed save.
      if (_pickedPhoto != null || _photoRemoved) {
        await _flushPhoto(productId, state);
      }
      // The sell tab is kept alive in an IndexedStack and would otherwise keep
      // selling the catalogue as it was before this save.
      if (mounted) context.read<HomeShellTabs>().markCatalogueChanged();
      widget.onSaved();
      if (mounted) Navigator.pop(context);
      // Push just this row to the backend after the editor closes. A price
      // change left only on the till would let the next till — or the web
      // report — keep selling at the old price until the next auto-sync, which
      // is up to six hours away. Best effort: a failed push is retried by the
      // next bulk sync, and must not turn a local save into an error.
      unawaited(_pushProductInBackground(product));
    } on StateError catch (error) {
      // A staged barcode clash names itself, because it is the owner's code that
      // is already spoken for and the message has to say by whom.
      if (mounted) setState(() => _error = error.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            "Couldn't save — check the phone has storage space free, then try again.");
      }
    }
  }

  /// Pushes the saved row to the backend, re-reading it so the local id and any
  /// newly assigned remote id are included.
  static Future<void> _pushProductInBackground(Product saved) async {
    try {
      if (saved.id == null) return;
      // `saved` already carries the id (checked above) and any remote_id that
      // was assigned during the save — re-reading the whole catalogue to find
      // the same row is a full-table scan on every product save.
      await BackendService.syncProductToBackend(saved);
    } catch (_) {
      // Offline, unlinked or the backend rejected it: the bulk auto-sync path
      // will pick the change up. Never block the local save on the network.
    }
  }

  @override
  Widget build(BuildContext context) {
    // The spacing scale, so the editor's rhythm is the app's rhythm. These used
    // to be raw `SizedBox(height: n)` values, which is how a form ends up with
    // 12, 8, 4 and 16 all meaning "between fields" at once — the congestion the
    // brief asked to remove, and a value no other screen shares.
    final AppSpacing spacing = AppSpacing.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
          start: spacing.xl,
          end: spacing.xl,
          top: spacing.xl),
      child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  widget.existing == null
                      ? AppLocalizations.of(context).inventoryAddProduct
                      : AppLocalizations.of(context).inventoryEditProduct,
                  style: Theme.of(context).textTheme.titleLarge),
              SizedBox(height: spacing.lg),
              TextField(
                  controller: _name,
                  decoration: InputDecoration(
                      labelText:
                          AppLocalizations.of(context).inventoryFieldName)),
              SizedBox(height: spacing.md),
              TextField(
                  controller: _category,
                  decoration: InputDecoration(
                      labelText:
                          AppLocalizations.of(context).inventoryFieldCategory)),
              SizedBox(height: spacing.md),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _cost,
                        decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)
                                .inventoryFieldCostPrice),
                        keyboardType: TextInputType.number)),
                SizedBox(width: spacing.md),
                Expanded(
                    child: TextField(
                        controller: _price,
                        decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)
                                .inventoryFieldSellPrice),
                        keyboardType: TextInputType.number)),
              ]),
              SizedBox(height: spacing.md),
              TextField(
                  controller: _bottleMl,
                  decoration: InputDecoration(
                      labelText:
                          AppLocalizations.of(context).inventoryFieldSizeMl,
                      helperText: AppLocalizations.of(context)
                          .inventoryFieldSizeMlHelper),
                  keyboardType: TextInputType.number),
              if (_visibleSizeSuggestions.isNotEmpty) _sizeSuggestionChips(),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _halfPrice,
                        decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)
                                .inventoryFieldHalfPriceOptional),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true))),
                SizedBox(width: spacing.md),
                Expanded(
                    child: TextField(
                        controller: _quarterPrice,
                        decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)
                                .inventoryFieldQuarterPriceOptional),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true))),
              ]),
              SizedBox(height: spacing.md),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _stock,
                        decoration: InputDecoration(
                            labelText: _trackVariants
                                ? AppLocalizations.of(context)
                                    .inventoryFieldTotalStock
                                : AppLocalizations.of(context)
                                    .inventoryFieldStockQty,
                            helperText: _trackVariants
                                ? AppLocalizations.of(context)
                                    .inventoryStockIsDerived
                                : null),
                        keyboardType: TextInputType.number)),
                SizedBox(width: spacing.md),
                Expanded(
                    child: TextField(
                        controller: _reorder,
                        decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)
                                .inventoryFieldReorderLevel),
                        keyboardType: TextInputType.number)),
              ]),
              SizedBox(height: spacing.md),
              TextField(
                  controller: _stamp,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)
                          .inventoryExciseStampField)),
              SizedBox(height: spacing.md),
              _PhotoRow(
                existingPath: widget.existing?.imagePath,
                picked: _pickedPhoto,
                removed: _photoRemoved,
                importing: _importingPhoto,
                onPick: _pickPhoto,
                onRemove: () => setState(() {
                  _photoRemoved = true;
                  _pickedPhoto = null;
                }),
                onUndoRemove: () => setState(() => _photoRemoved = false),
              ),
              SizedBox(height: spacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _trackVariants,
                onChanged: _setTrackVariants,
                title:
                    Text(AppLocalizations.of(context).inventorySoldAsVariants),
                // Says what turning it on does to the till, because the switch
                // is otherwise invisible in its consequences: with it on, the
                // product itself stops being sellable and its variants take over.
                subtitle: Text(_trackVariants
                    ? AppLocalizations.of(context)
                        .inventorySoldAsVariantsOnSubtitle
                    : AppLocalizations.of(context)
                        .inventorySoldAsVariantsOffSubtitle),
              ),
              if (_trackVariants) ...[
                Text(AppLocalizations.of(context).inventoryVariantsSection,
                    style: Theme.of(context).textTheme.titleSmall),
                SizedBox(height: spacing.sm),
                if (_loadingMeta)
                  const LinearProgressIndicator()
                else if (_drafts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                        AppLocalizations.of(context).inventoryNoVariantsHelper,
                        style: AppTypography.of(context).bodyMedium),
                  )
                else
                  for (var i = 0; i < _drafts.length; i++) _variantRow(i),
                OutlinedButton.icon(
                  onPressed: _addVariant,
                  icon: const Icon(Icons.add),
                  label: Text(_drafts.isEmpty
                      ? AppLocalizations.of(context).inventoryAddFirstVariant
                      : AppLocalizations.of(context)
                          .inventoryAddAnotherVariant),
                ),
                SizedBox(height: spacing.xl),
              ],
              Text(AppLocalizations.of(context).inventoryBarcodesSection,
                  style: Theme.of(context).textTheme.titleSmall),
              SizedBox(height: spacing.sm),
              Text(
                AppLocalizations.of(context).inventoryBarcodesHelp,
                style: AppTypography.of(context).bodySmall,
              ),
              SizedBox(height: spacing.md),
              if (_loadingMeta)
                const LinearProgressIndicator()
              else if (_codes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                      AppLocalizations.of(context).inventoryNoBarcodesYet,
                      style: AppTypography.of(context).bodyMedium),
                )
              else
                for (final code in _codes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                        code.isVariantLevel
                            ? Icons.label_outline
                            : Icons.qr_code,
                        size: 20),
                    title: Text(code.barcode,
                        style: const TextStyle(fontFamily: 'monospace')),
                    // The level is named, not implied: "this code adds the
                    // whole product" and "this code adds Dark" behave
                    // differently at the till and the owner has to be able to
                    // tell which they are looking at.
                    subtitle: Text(
                        '${code.scopeLabel} · ${BarcodeKind.label(code.kind)}'),
                    // Relabelling is a tap rather than a dropdown because there
                    // are three kinds and only one reason to change them; the
                    // affordance is discoverable without a dialog.
                    onTap: () => _cycleBarcodeKind(code),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: AppLocalizations.of(context)
                          .inventoryRemove(code.barcode),
                      onPressed: () => _removeBarcode(code),
                    ),
                  ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _barcode,
                    decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context).inventoryAddBarcode,
                        hintText:
                            AppLocalizations.of(context).inventoryBarcodeHint),
                    // Digits and letters only: what a scanner could emit.
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9\-]')),
                    ],
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => _addBarcode(),
                  ),
                ),
                SizedBox(width: spacing.md),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add barcode',
                  onPressed: _addBarcode,
                ),
              ]),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              SizedBox(height: spacing.xl),
              FilledButton(
                  onPressed: _save,
                  // Says what the button will do: on a product with variants
                  // staged, this is one save of the product *and* them, not a
                  // save of the product alone.
                  child: Text(_trackVariants && _drafts.isNotEmpty
                      ? 'Save product and ${_drafts.length} variant${_drafts.length == 1 ? '' : 's'}'
                      : 'Save product')),
              SizedBox(height: spacing.xl),
            ]),
      ),
    );
  }
}

/// Asks for the shop-wide low-stock limit.
///
/// A number, not a switch: the whole point is that a shop's limit is a count of
/// units it wants warning at, and "on" says nothing. The consequence is stated
/// in the dialog because the write touches every active product.
class _LowStockLimitDialog extends StatefulWidget {
  const _LowStockLimitDialog({required this.title, required this.initial});

  final String title;
  final int initial;

  @override
  State<_LowStockLimitDialog> createState() => _LowStockLimitDialogState();
}

class _LowStockLimitDialogState extends State<_LowStockLimitDialog> {
  late final TextEditingController _limit =
      TextEditingController(text: widget.initial.toString());

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _limit,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: l10n.inventoryLowStockLimitTitle),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () {
            final int? value = int.tryParse(_limit.text.trim());
            if (value == null || value < 0) return;
            Navigator.pop(context, value);
          },
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}

class _AdjustDialog extends StatefulWidget {
  final Product product;

  /// Set when the correction applies to one variant rather than the product.
  final ProductVariant? variant;

  const _AdjustDialog({required this.product, this.variant});
  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _delta = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _delta.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.variant == null
          ? AppLocalizations.of(context)
              .inventoryAdjustStockTitle(widget.product.name)
          : AppLocalizations.of(context)
              .inventoryAdjustStockTitle(widget.variant!.label)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: _delta,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: InputDecoration(
                labelText: AppLocalizations.of(context).inventoryDeltaLabel)),
        TextField(
            controller: _reason,
            decoration: InputDecoration(
                labelText: AppLocalizations.of(context).inventoryReasonLabel)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
              context, {'delta': _delta.text, 'reason': _reason.text}),
          child: Text(AppLocalizations.of(context).inventorySaveAction),
        ),
      ],
    );
  }
}

/// The stock count on a product or variant row.
///
/// Was a `CircleAvatar` tinted red or green by `isLow`. That is the
/// colour-alone rule in its plainest form: a shopkeeper with deuteranopia, or a
/// greyscale screenshot in a bug report, or a screen reader, learns nothing from
/// a red circle. The count is still the number — but the TONE comes from
/// [StatusTone], which carries a glyph and a word alongside the colour, and the
/// badge is excluded from the row's own semantics because the row announces the
/// count already.
class _StockCountBadge extends StatelessWidget {
  const _StockCountBadge({required this.quantity, required this.tone});

  final int quantity;

  /// The row's state, carried by the badge so the count and the state are read
  /// as one thing at the leading edge of the list.
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);

    return Semantics(
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.of(context).sm,
        ),
        decoration: BoxDecoration(
          color: tone.container(colors),
          shape: BoxShape.rectangle,
          borderRadius: AppShapes.of(context).chipRadius,
          border: tone.isFilled ? Border.all(color: tone.color(colors)) : null,
        ),
        child: Text(
          AppLocalizations.of(context).inventoryQuantity(quantity),
          // Tabular figures: a column of stock counts that shifts sideways as
          // the digit count changes is unreadable at a glance.
          style: AppTypography.money(
            context,
            size: 14,
            weight: FontWeight.w700,
          ).copyWith(color: tone.onContainer(colors)),
        ),
      ),
    );
  }
}
