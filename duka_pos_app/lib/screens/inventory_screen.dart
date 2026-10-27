import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:provider/provider.dart';
import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/audit_log.dart';
import '../models/models.dart';
import '../models/stock_movement.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../ui/dialogs/manager_approval_sheet.dart';
import '../services/audit_actor.dart';
import '../services/barcode/barcode_service.dart';
import '../services/backend_service.dart';
import '../services/live_refresh_mixin.dart';
import '../services/live_channel_service.dart';
import '../services/session_refresh_mixin.dart';
import '../services/workspace_service.dart';
import '../services/printer/label_builder.dart';
import '../services/printer/printer_config.dart';
import '../services/printer/receipt_printer.dart';
import '../ui/components/controls.dart';
import '../screens/deliveries_history_sheet.dart';
import '../screens/receive_stock_sheet.dart';
import '../utils/error_utils.dart';
import '../utils/money.dart';
import '../utils/text_input.dart';
import '../utils/units.dart';
import '../widgets/variant_catalogue.dart';
import '../widgets/variant_form_sheet.dart';
import '../routing/home_shell.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/screen_title.dart';
import '../ui/components/operation_result.dart';
import '../ui/components/status.dart';
import 'package:image_picker/image_picker.dart';
import '../services/product_image_store.dart';
import '../ui/components/product_photo.dart';
import '../utils/validation_utils.dart';
import 'tank_form_sheet.dart';
import 'stocktake_screen.dart';
import 'reorder_screen.dart';
import '../models/product_pack.dart';
import '../profile/profile_navigation.dart';
import '../profile/shop_profile.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({this.focusedProductId, super.key});

  final String? focusedProductId;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with LiveRefresh<InventoryScreen>, SessionRefresh<InventoryScreen> {
  List<Product> _products = [];

  bool _loading = true;

  VariantCatalogue _variants = VariantCatalogue.empty;

  int _lowStockLimit = 5;

  @override
  Set<LiveReason> get liveReasons => const <LiveReason>{
        LiveReason.products,
        LiveReason.stock,
      };

  @override
  bool get liveIsVisible => TickerMode.valuesOf(context).enabled;

  @override
  Future<void> reloadFromLive() => _load();

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
    final includeVariants =
        context.read<AppState>().shopProfile.navigation.showVariants;
    final p = await DatabaseHelper.instance.getProducts();
    final catalogue = await VariantCatalogue.load(
      includeVariants: includeVariants,
    );
    final int? limit = p
        .where((Product product) => product.reorderLevel > 0)
        .map((Product product) => product.reorderLevel)
        .fold<int?>(
            null,
            (int? common, int level) =>
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
      builder: (_) => _ProductEditor(
        existing: existing,
        allowVariants:
            context.read<AppState>().shopProfile.navigation.showVariants,
        shopProfile: context.read<AppState>().shopProfile,
        onSaved: _load,
      ),
    );
  }

  Future<void> _managePacks(Product product) async {
    if (product.id == null) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPacksSheet(product: product),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _repackStock() async {
    final state = context.read<AppState>();
    final l10n = AppLocalizations.of(context);
    if (!state.hasPermission(PermissionKey.adjustStock)) return;
    if (!state.isOwnerSession &&
        state.permissionMode(PermissionKey.adjustStock) ==
            PermissionMode.approval) {
      final approver = await showManagerApprovalSheet(
        context,
        purpose: l10n.inventoryRepackTitle,
      );
      if (!mounted || approver == null) return;
    }
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _RepackDialog(products: _products),
    );
    if (result == null || !mounted) return;
    final sourceId = int.tryParse(result['source_id'] ?? '');
    final outputId = int.tryParse(result['output_id'] ?? '');
    final sourceQty = double.tryParse(result['source_qty'] ?? '');
    final outputQty = double.tryParse(result['output_qty'] ?? '');
    if (sourceId == null ||
        outputId == null ||
        sourceQty == null ||
        outputQty == null) {
      return;
    }
    final staffName = state.currentStaffName ?? 'Owner';
    try {
      await DatabaseHelper.instance.repackStock(
        sourceProductId: sourceId,
        outputProductId: outputId,
        sourceQty: sourceQty,
        outputQty: outputQty,
        staffName: staffName,
        staffId: state.currentStaffId,
      );
      await _audit(
        AuditAction.stockAdjusted,
        AuditEntity.product,
        entityId: 'id-$sourceId',
        detail: 'repack $sourceQty → $outputQty into product $outputId',
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.inventoryRepackSaved),
        ));
      }
    } on Object catch (error) {
      if (!mounted) return;
      final message = error.toString().contains('more source stock')
          ? l10n.inventoryRepackInsufficientStock
          : l10n.inventoryRepackFailed;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _assignInternalBarcode(Product product) async {
    if (product.id == null) return;
    final code = Barcode.internalEan13(itemNumber: product.id!);
    final saved = await DatabaseHelper.instance.addBarcode(
      productId: product.id!,
      barcode: code,
      kind: BarcodeKind.own,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(saved
          ? 'Internal barcode assigned: $code'
          : 'This product already has that barcode.'),
    ));
  }

  Future<void> _printBarcodeLabel(Product product) async {
    if (product.id == null) return;
    final codes =
        await DatabaseHelper.instance.getBarcodesForProduct(product.id!);
    if (!mounted) return;
    if (codes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Assign a barcode before printing its label.'),
      ));
      return;
    }
    final quantityController = TextEditingController(text: '1');
    final int? quantity = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Print barcode labels'),
        content: TextField(
          controller: quantityController,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Number of labels',
            helperText: 'The batch can be retried if the printer is busy.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              int.tryParse(quantityController.text.trim()),
            ),
            child: const Text('Print'),
          ),
        ],
      ),
    );
    quantityController.dispose();
    if (quantity == null || quantity < 1 || quantity > 100 || !mounted) return;
    final config = await PrinterConfig.load();
    final jobId = await DatabaseHelper.instance.createLabelPrintJob(
      uuid: 'label-job-${DateTime.now().microsecondsSinceEpoch}',
      productId: product.id!,
      productName: product.name,
      barcode: codes.first.barcode,
      priceMinor: product.sellPrice.minorUnits,
      quantity: quantity,
      paperWidth: config.paperWidth.mm,
    );
    await _runLabelPrintJob(jobId, config);
  }

  Future<void> _runLabelPrintJob(int jobId, PrinterConfig config) async {
    final job = await DatabaseHelper.instance.getLabelPrintJob(jobId);
    if (job == null || !mounted) return;
    final total = (job['quantity'] as num).toInt();
    var printed = (job['printed_quantity'] as num).toInt();
    if (!config.isConfigured) {
      await DatabaseHelper.instance.updateLabelPrintJob(
        id: jobId,
        status: 'pending',
        error: 'Printer is not configured',
      );
      if (mounted) {
        _showLabelJobMessage(
            jobId, 'Turn on the receipt printer in Settings first.');
      }
      return;
    }
    final labels = List<BarcodeLabel>.generate(
      total,
      (_) => BarcodeLabel(
        name: job['product_name'] as String,
        barcode: job['barcode'] as String,
        price: Money.fromMinor((job['price_minor'] as num).toInt()),
      ),
    );
    final printer = ReceiptPrinter();
    while (printed < total) {
      final end = (printed + 20).clamp(0, total);
      final result = await printer.printLabels(
        labels: labels.sublist(printed, end),
        config: config,
      );
      if (!result.printed) {
        await DatabaseHelper.instance.updateLabelPrintJob(
          id: jobId,
          printedQuantity: printed,
          status: 'pending',
          error: result.outcome.name,
        );
        if (mounted) {
          _showLabelJobMessage(
              jobId, 'The barcode label batch could not be completed.');
        }
        return;
      }
      printed = end;
      await DatabaseHelper.instance.updateLabelPrintJob(
        id: jobId,
        printedQuantity: printed,
        status: printed == total ? 'completed' : 'printing',
      );
    }
    if (!mounted) return;
    _showLabelJobMessage(jobId, '$total barcode labels sent to the printer.');
  }

  void _showLabelJobMessage(int jobId, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      action: message.contains('could not')
          ? SnackBarAction(
              label: 'Retry',
              onPressed: () async => _runLabelPrintJob(
                jobId,
                await PrinterConfig.load(),
              ),
            )
          : null,
    ));
  }

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
    final state = context.read<AppState>();
    if (!state.isOwnerSession &&
        state.permissionMode(PermissionKey.adjustStock) ==
            PermissionMode.approval) {
      final approver = await showManagerApprovalSheet(
        context,
        purpose: 'Approve the stock adjustment for ${p.name}',
      );
      if (!mounted || approver == null) return;
    }
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
      //
      // The push is in its OWN try, outside the adjustment's. The local write
      // has already succeeded by this point, so an exception from the push
      // must never be reported as a failed adjustment — the natural response
      // to "the adjustment failed" is to run it again, and running it again
      // applies the delta twice.
      var pushed = false;
      if (mounted) {
        try {
          pushed = await BackendService.adjustStockOnBackend(
            product: p,
            delta: delta,
            reason: result['reason'],
            staffProfileId: staffRemoteId,
          );
        } catch (_) {
          pushed = false;
        }
      }
      if (!pushed && mounted) {
        // Saved on this phone, not on the server. Said plainly, because a
        // till that shows the same message for a success and a partial
        // success cannot be trusted with either.
        showOperationSuccess(
          context,
          title: AppLocalizations.of(context).inventoryStockSavedTitle,
          message: AppLocalizations.of(context).inventoryStockSavedLocally,
          detailIcon: Icons.cloud_off_outlined,
        );
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

  /// Records a Drinks waste/spillage as an append-only write-off movement.
  ///
  /// The quantity is deliberately decimal: a tank can lose half a stock unit,
  /// and forcing that through the whole-number correction dialog would turn a
  /// measured variance into a false bottle count.
  Future<void> _recordWaste(Product p) async {
    final state = context.read<AppState>();
    if (!state.isOwnerSession &&
        state.permissionMode(PermissionKey.adjustStock) ==
            PermissionMode.approval) {
      final approver = await showManagerApprovalSheet(
        context,
        purpose: 'Approve waste recorded for ${p.name}',
      );
      if (!mounted || approver == null) return;
    }
    final quantityController = TextEditingController();
    final reasonController = TextEditingController(text: 'Waste/spillage');
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Record waste · ${p.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: quantityController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quantity wasted',
                helperText: 'Use the product stock unit; decimals are allowed.',
              ),
            ),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, <String, String>{
              'quantity': quantityController.text.trim(),
              'reason': reasonController.text.trim(),
            }),
            child: const Text('Record waste'),
          ),
        ],
      ),
    );
    quantityController.dispose();
    reasonController.dispose();
    if (result == null || !mounted) return;
    final quantity = double.tryParse(result['quantity'] ?? '');
    if (quantity == null || !quantity.isFinite || quantity <= 0) return;
    if (quantity > p.stockQty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Waste cannot be greater than current stock.'),
      ));
      return;
    }
    final staffName = state.currentStaffName ?? 'Unknown';
    int? staffId;
    String? staffRemoteId;
    if (!state.isOwnerSession) {
      final staff = await DatabaseHelper.instance.getStaff();
      final match = staff.where((entry) => entry.name == staffName);
      staffId = match.isEmpty ? null : match.first.id;
      staffRemoteId = match.isEmpty ? null : match.first.remoteId;
    }
    try {
      await DatabaseHelper.instance.adjustStock(
        StockAdjustment(
          productId: p.id!,
          productName: p.name,
          delta: -quantity,
          reason: result['reason']?.isNotEmpty == true
              ? result['reason']!
              : 'Waste/spillage',
          staffName: staffName,
          createdAt: DateTime.now().toIso8601String(),
        ),
        staffId: staffId,
        movementType: StockMovementType.writeoff,
      );
      await _audit(
        AuditAction.stockAdjusted,
        AuditEntity.product,
        entityId: 'id-${p.id}',
        detail: 'waste -$quantity ${result['reason'] ?? 'Waste/spillage'}',
      );
      await _load();
      var pushed = false;
      try {
        pushed = await BackendService.adjustStockOnBackend(
          product: p,
          delta: -quantity,
          reason: result['reason'],
          staffProfileId: staffRemoteId,
        );
      } catch (_) {
        pushed = false;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(pushed
              ? 'Waste recorded and synced.'
              : 'Waste recorded on this till; sync is pending.'),
        ));
      }
    } on Object catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Waste could not be recorded.'),
        ));
      }
    }
  }

  /// Corrects the stock of one variant of a product sold as variants.
  ///
  /// Deliberately not pushed to the backend: the adjustment API takes a product
  /// and adjusts *that* product's count, and this count belongs to a variant.

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
        title: Text(
            AppLocalizations.of(dialogContext).inventoryWhichVariant(p.name)),
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
    // The SHARED dialog, not a hand-rolled one. A hand-rolled dialog is where
    // the wrong navigator gets popped: `showDialog` pushes onto the root
    // navigator, so `Navigator.pop` with the SCREEN's context closes the
    // screen behind the dialog instead of the dialog itself — which is how
    // "delete product" used to leave the whole inventory screen.
    final ConfirmOutcome outcome = await confirmIrreversible(
      context,
      title: l10n.inventoryDeleteTitle,
      message: l10n.inventoryDeleteMessage(p.name),
      confirmLabel: l10n.inventoryDeleteAction,
      cancelLabel: l10n.actionCancel,
      // A deactivation is not a destruction: the row stays, the past sales
      // still point at it, and the owner can bring it back.
      isDestructive: false,
    );
    if (outcome is! ConfirmAccepted) return;
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

  /// Records a delivery: what arrived, and what it cost.
  ///
  /// Records a delivery: what arrived, and what it cost.
  ///
  /// The products, the suppliers, the draft and the costing mode are read
  /// HERE, before the sheet opens, because a sheet that reads the database
  /// while it is building itself does its I/O in the middle of a build.
  Future<void> _receiveStock() async {
    final AppState state = context.read<AppState>();
    if (!state.isOwnerSession &&
        state.permissionMode(PermissionKey.receiveStock) ==
            PermissionMode.approval) {
      final approver = await showManagerApprovalSheet(
        context,
        purpose: 'Approve receiving new stock',
      );
      if (!mounted || approver == null) return;
    }
    final DatabaseHelper db = DatabaseHelper.instance;
    final List<Product> products = await db.getProducts();
    final List<Supplier> suppliers = await db.getSuppliers();
    // A session the app killed last time comes back as a draft, offered —
    // not forced, because the delivery could have been finished on paper.
    final Map<String, dynamic>? draftJson =
        await db.getReceiveDraft(state.currentStaffId);
    final ReceiveDraftSnapshot? draft =
        draftJson == null ? null : ReceiveDraftSnapshot.fromJson(draftJson);
    final String costingMode = await db.getCostingMode();
    if (!mounted) return;
    final int? receiptId = await showReceiveStockSheet(
      context,
      products: products,
      suppliers: suppliers,
      lastCostFor: db.lastCostForProduct,
      staffName: state.currentStaffName ?? '',
      staffId: state.currentStaffId,
      costingMode: costingMode,
      draft: draft,
    );
    if (receiptId == null || !mounted) return;
    await _load();
    if (!mounted) return;
    if (receiptId == 0) {
      // A resumed draft was discarded; nothing was posted, and the draft is
      // already gone. Say what happened rather than nothing at all.
      showOperationSuccess(
        context,
        title: AppLocalizations.of(context).receiveTitle,
        message: AppLocalizations.of(context).receiveDraftDiscarded,
      );
      return;
    }
    // The outcome is a POPUP, not a screen: the till is not blocked.
    final AppLocalizations l10n = AppLocalizations.of(context);
    showOperationSuccess(
      context,
      title: l10n.receiveTitle,
      message: l10n.receiveDone,
    );
  }

  /// The deliveries so far, with the owner's void. A modal history over the
  /// inventory: read by the CALLER (the receipts with their supplier names),
  /// so it opens without I/O in its own build.
  Future<void> _openDeliveries() async {
    final AppState state = context.read<AppState>();
    final DatabaseHelper db = DatabaseHelper.instance;
    final List<StockReceipt> receipts = await db.getStockReceipts();
    final Map<int, String> supplierNames = <int, String>{
      for (final Supplier supplier in await db.getSuppliers())
        if (supplier.id != null) supplier.id!: supplier.name,
    };
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => DeliveriesHistorySheet(
        receipts: receipts,
        supplierNames: supplierNames,
        canVoid: state.isOwnerSession,
        staffId: state.currentStaffId,
        staffName: state.currentStaffName ?? '',
      ),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isOwner = appState.isOwnerSession;
    final canReceive = appState.hasPermission(PermissionKey.receiveStock);
    final canStocktake = appState.hasPermission(PermissionKey.stocktake);
    final canReorder = appState.hasPermission(PermissionKey.manageSuppliers);
    final showDrinkService = appState.shopProfile.navigation.showDrinkService;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: l10n.inventoryAddProduct,
        child: const Icon(Icons.add),
      ),
      // A tank is not another kind of bottle: it is a drum you pour out and
      // sell by the cup, so it gets its own form rather than one more option
      // on this screen's product editor.
      // The footer's stock action is deliberately manual: buying stock does
      // not create an order or trigger any automatic purchasing in this
      // version. The receive flow records what actually arrived and its cost.
      //
      // Receiving stock is for managers AND owners — it is the shop's stock
      // coming in, and the money it cost. A tank is the owner's own setup
      // decision, so it stays behind the owner's door.
      persistentFooterButtons: <Widget>[
        if (canReceive)
          TextButton.icon(
            onPressed: () => _receiveStock(),
            icon: const Icon(Icons.local_shipping_outlined, size: 18),
            label: Text(l10n.inventoryManualRestock),
          ),
        if (canReceive)
          TextButton.icon(
            onPressed: () => _openDeliveries(),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: Text(l10n.receiveDeliveriesAction),
          ),
        if (canStocktake)
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const StocktakeScreen()),
            ),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Stocktake'),
          ),
        if (canReorder)
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ReorderScreen()),
            ),
            icon: const Icon(Icons.playlist_add_check_outlined, size: 18),
            label: const Text('Reorder'),
          ),
        if (isOwner && showDrinkService)
          TextButton.icon(
            onPressed: () => showTankFormSheet(context),
            icon: const Icon(Icons.propane_tank_outlined, size: 18),
            label: Text(l10n.tankAddEntry),
          ),
        if ((appState.shopProfile == ShopProfile.duka ||
            appState.shopProfile == ShopProfile.drinks) &&
            appState.hasPermission(PermissionKey.adjustStock))
          TextButton.icon(
            onPressed: _repackStock,
            icon: const Icon(Icons.swap_horiz_outlined, size: 18),
            label: Text(l10n.inventoryRepackAction),
          ),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The screen's own title, large, on the canvas.
            //
            // It used to be a brand strip: a logo and the wordmark, and no
            // name for the screen itself. A screen that opens with a logo has
            // spent its first line on the product instead of on the stock, and
            // the shell's bar already carries the mark.
            ScreenTitle(
              title: l10n.navInventory,
              padding: EdgeInsetsDirectional.only(
                start: AppSpacing.of(context).xl,
                end: AppSpacing.of(context).xl,
                top: AppSpacing.of(context).sm,
                bottom: AppSpacing.of(context).sm,
              ),
            ),
            Expanded(
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
                          return _InventoryEmptyState(
                              onAdd: () => _openEditor());
                        }
                        // Row zero is the shot-cup entry rather than a product: it is a
                        // way of selling what is already in the catalogue, not another
                        // line of it, and burying it under the first hundred sodas is
                        // how a bar never finds the feature that makes it a bar.
                        if (_products.isEmpty || i == 0) {
                          return Column(
                            children: <Widget>[
                              if (showDrinkService)
                                Semantics(
                                  label: l10n.inventoryShotCupsSpoken,
                                  child: ListTile(
                                    leading:
                                        const Icon(Icons.local_drink_outlined),
                                    title: Text(l10n.inventoryShotCupsTitle),
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
                                subtitle: Text(
                                    l10n.inventoryLowStockLimitSubtitle(
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
                            onWaste:
                                showDrinkService ? () => _recordWaste(p) : null,
                            onPacks: () => _managePacks(p),
                            onAssignBarcode: () => _assignInternalBarcode(p),
                            onPrintBarcode: () => _printBarcodeLabel(p),
                            onDelete: () => _delete(p),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Divider inset that lines the rule up with the product name rather than the
  /// screen edge — the badge is the row's anchor, the text is what the rule

  double _rowDividerInset(BuildContext context) =>
      AppSpacing.of(context).md + 40 + AppSpacing.of(context).md;
}

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

class _RepackDialog extends StatefulWidget {
  const _RepackDialog({required this.products});

  final List<Product> products;

  @override
  State<_RepackDialog> createState() => _RepackDialogState();
}

class _RepackDialogState extends State<_RepackDialog> {
  late int? _sourceId =
      widget.products.isEmpty ? null : widget.products.first.id;
  late int? _outputId =
      widget.products.length < 2 ? null : widget.products[1].id;
  final _sourceQty = TextEditingController();
  final _outputQty = TextEditingController();

  @override
  void dispose() {
    _sourceQty.dispose();
    _outputQty.dispose();
    super.dispose();
  }

  void _save() {
    final sourceQty = double.tryParse(_sourceQty.text.trim());
    final outputQty = double.tryParse(_outputQty.text.trim());
    if (_sourceId == null ||
        _outputId == null ||
        _sourceId == _outputId ||
        sourceQty == null ||
        outputQty == null ||
        !sourceQty.isFinite ||
        !outputQty.isFinite ||
        sourceQty <= 0 ||
        outputQty <= 0) {
      return;
    }
    Navigator.of(context).pop(<String, String>{
      'source_id': '$_sourceId',
      'output_id': '$_outputId',
      'source_qty': '$sourceQty',
      'output_qty': '$outputQty',
    });
  }

  String _label(int? id) =>
      widget.products.firstWhere((product) => product.id == id).name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.inventoryRepackTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DropdownButtonFormField<int>(
              initialValue: _sourceId,
              decoration:
                  InputDecoration(labelText: l10n.inventoryRepackSourceProduct),
              items: [
                for (final product in widget.products)
                  DropdownMenuItem<int>(
                    value: product.id,
                    child: Text('${product.name} · ${product.stockQty}'),
                  ),
              ],
              onChanged: (value) => setState(() => _sourceId = value),
            ),
            TextField(
              controller: _sourceQty,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.inventoryRepackSourceQuantity,
                helperText: l10n.inventoryRepackSourceHelp,
              ),
            ),
            DropdownButtonFormField<int>(
              initialValue: _outputId,
              decoration:
                  InputDecoration(labelText: l10n.inventoryRepackOutputProduct),
              items: [
                for (final product in widget.products)
                  DropdownMenuItem<int>(
                    value: product.id,
                    child: Text(_label(product.id)),
                  ),
              ],
              onChanged: (value) => setState(() => _outputId = value),
            ),
            TextField(
              controller: _outputQty,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.inventoryRepackOutputQuantity,
                helperText: l10n.inventoryRepackOutputHelp,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.inventoryRepackCancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.inventoryRepackRecord)),
      ],
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
    this.onWaste,
    required this.onPacks,
    required this.onAssignBarcode,
    required this.onPrintBarcode,
    required this.onDelete,
    super.key,
  });

  final Product product;
  final int variantCount;
  final bool tracksVariants;
  final bool isOwner;
  final VoidCallback onEdit;
  final VoidCallback onAdjust;
  final VoidCallback? onWaste;
  final VoidCallback onPacks;
  final VoidCallback onAssignBarcode;
  final VoidCallback onPrintBarcode;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);

    final bool isOut = product.stockQty <= 0;
    final bool isLow = !isOut && product.isLow;

    // The state, resolved ONCE from the value.
    //
    // EVERY row wears a state, including the ones that are fine. A shopkeeper
    // scanning for what to reorder is looking for the amber row, and a green
    // chip on every other row is what makes the amber one findable — the same
    // way one alarm in a room of quiet indicators is the only thing anybody
    // looks at. It is not a second green badge: the COUNT on the leading edge
    // is neutral, and the chip beside the name carries the state.
    final StatusTone tone = isOut
        ? StatusTone.danger
        : isLow
            ? StatusTone.warning
            : StatusTone.success;

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
            // The floor is on the ROW, not the text: the shared 56px field
            // dimension gives the target room while the name remains free to
            // wrap at larger text scales.
            constraints: BoxConstraints(minHeight: spacing.textFieldHeight),
            child: Row(
              children: [
                // The photograph, when the product has one.
                //
                // The row is where the owner MANAGES photographs, so a row
                // with a picture and a row without one have to be told apart
                // at a glance: the picture is the thing that says "this is
                // the one with the photograph". It is decoration — the row
                // itself is the button — so it stays out of the semantics,
                // where the row's own label already names the product.
                //
                // The row's `updated_at` comes with it: a photograph that was
                // replaced is written over the file at the SAME path, and the
                // row would otherwise go on drawing the old picture.
                if (product.imagePath != null) ...<Widget>[
                  ExcludeSemantics(
                    child: ProductPhoto(
                      imagePath: product.imagePath,
                      size: 40,
                      revision: product.updatedAt,
                    ),
                  ),
                  SizedBox(width: spacing.md),
                ],
                _StockCountBadge(
                  quantity: product.stockQty.round(),
                  // The COUNT is a number, not a state: it stays neutral so the
                  // only coloured thing on the row is the state chip.
                  tone: StatusTone.neutral,
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
                        style: type.titleSmall,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        meta,
                        style: type.bodySmall?.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                      // The state chip, on EVERY row.
                      //
                      // The green one is a deep, quiet wash and the amber one
                      // is bright, so the row that needs attention is the row
                      // the eye lands on — which is the whole point of a
                      // stock list.
                      SizedBox(height: spacing.xs),
                      StatusChip(
                        tone: tone,
                        text: isOut
                            ? l10n.inventoryOutOfStock
                            : isLow
                                ? l10n.inventoryLowStock
                                : l10n.inventoryInStock,
                      ),
                    ],
                  ),
                ),
                _ProductActionMenu(
                  isOwner: isOwner,
                  onEdit: onEdit,
                  onAdjust: onAdjust,
                  onWaste: onWaste,
                  onPacks: onPacks,
                  onAssignBarcode: onAssignBarcode,
                  onPrintBarcode: onPrintBarcode,
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
    this.onWaste,
    required this.onPacks,
    required this.onAssignBarcode,
    required this.onPrintBarcode,
    required this.onDelete,
  });

  final bool isOwner;
  final VoidCallback onEdit;
  final VoidCallback onAdjust;
  final VoidCallback? onWaste;
  final VoidCallback onPacks;
  final VoidCallback onAssignBarcode;
  final VoidCallback onPrintBarcode;
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
          case 'waste':
            onWaste?.call();
            break;
          case 'packs':
            onPacks();
            break;
          case 'barcode':
            onAssignBarcode();
            break;
          case 'print-barcode':
            onPrintBarcode();
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
        if (onWaste != null)
          const PopupMenuItem(
            value: 'waste',
            child: Row(
              children: [
                Icon(Icons.delete_sweep_outlined, size: 20),
                SizedBox(width: 12),
                Text('Record waste/spillage'),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'packs',
          child: Row(
            children: const [
              Icon(Icons.inventory_2_outlined, size: 20),
              SizedBox(width: 12),
              Text('Packs and cartons'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'barcode',
          child: Row(
            children: [
              Icon(Icons.qr_code_2_outlined, size: 20),
              SizedBox(width: 12),
              Text('Assign internal barcode'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'print-barcode',
          child: Row(
            children: [
              Icon(Icons.print_outlined, size: 20),
              SizedBox(width: 12),
              Text('Print barcode label'),
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

class _ProductPacksSheet extends StatefulWidget {
  const _ProductPacksSheet({required this.product});

  final Product product;

  @override
  State<_ProductPacksSheet> createState() => _ProductPacksSheetState();
}

class _ProductPacksSheetState extends State<_ProductPacksSheet> {
  List<ProductPack> _packs = const <ProductPack>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final packs =
        await DatabaseHelper.instance.getProductPacks(widget.product.id!);
    if (!mounted) return;
    setState(() {
      _packs = packs;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _PackFormDialog(),
    );
    if (result == null) return;
    try {
      await DatabaseHelper.instance.addProductPack(
        uuid: 'pack-${DateTime.now().microsecondsSinceEpoch}',
        productId: widget.product.id!,
        name: result['name']!,
        barcode: result['barcode']!,
        unitsPerPack: double.parse(result['units']!),
        unitCost: Money.fromMajor(double.parse(result['cost']!)),
        sellPrice: result['sell']!.trim().isEmpty
            ? null
            : Money.fromMajor(double.parse(result['sell']!)),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save pack: $error')),
      );
    }
  }

  Future<void> _deactivate(ProductPack pack) async {
    await DatabaseHelper.instance.deactivateProductPack(pack.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${widget.product.name} packs',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_loading)
                const LinearProgressIndicator()
              else if (_packs.isEmpty)
                const Text(
                    'No packs yet. Add a case, carton or bundle barcode.'),
              ..._packs.map((pack) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(pack.name),
                    subtitle: Text(
                        '${pack.unitsPerPack} base units · ${pack.barcode} · cost ${formatMoney(pack.unitCost)}'),
                    trailing: IconButton(
                      tooltip: 'Deactivate pack',
                      onPressed: () => _deactivate(pack),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  )),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Add pack'),
              ),
            ],
          ),
        ),
      );
}

class _PackFormDialog extends StatefulWidget {
  const _PackFormDialog();

  @override
  State<_PackFormDialog> createState() => _PackFormDialogState();
}

class _PackFormDialogState extends State<_PackFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _barcode = TextEditingController();
  final _units = TextEditingController(text: '1');
  final _cost = TextEditingController();
  final _sell = TextEditingController();

  @override
  void dispose() {
    for (final controller in [_name, _barcode, _units, _cost, _sell]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop({
      'name': _name.text.trim(),
      'barcode': _barcode.text.trim(),
      'units': _units.text.trim(),
      'cost': _cost.text.trim(),
      'sell': _sell.text.trim(),
    });
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String? _positive(String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    return number == null || number <= 0 ? 'Enter a positive number' : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add pack or carton'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: _required),
                TextFormField(
                    controller: _barcode,
                    decoration:
                        const InputDecoration(labelText: 'Pack barcode'),
                    validator: _required),
                TextFormField(
                    controller: _units,
                    decoration:
                        const InputDecoration(labelText: 'Base units per pack'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: _positive),
                TextFormField(
                    controller: _cost,
                    decoration: const InputDecoration(labelText: 'Pack cost'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: _positive),
                TextFormField(
                    controller: _sell,
                    decoration: const InputDecoration(
                        labelText: 'Pack selling price (optional)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) =>
                        value!.trim().isEmpty ? null : _positive(value)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}

/// The photograph controls for one product.
///
/// Its own widget rather than inline in the editor's `build` because it holds

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

  final String? existingPath;

  final File? picked;

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
            borderRadius: AppShapes.of(context).controlRadius,
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

class _UnitPicker extends StatelessWidget {
  const _UnitPicker({
    required this.value,
    required this.onChanged,
    required this.showMeasuredGoods,
  });

  final ProductUnit value;
  final ValueChanged<ProductUnit> onChanged;
  final bool showMeasuredGoods;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final options = <SegmentedOption<ProductUnit>>[
      SegmentedOption<ProductUnit>(
          value: ProductUnit.each, label: l10n.productUnitEach),
      if (showMeasuredGoods || value == ProductUnit.litre)
        SegmentedOption<ProductUnit>(
            value: ProductUnit.litre, label: l10n.productUnitLitre),
      if (showMeasuredGoods || value == ProductUnit.millilitre)
        SegmentedOption<ProductUnit>(
            value: ProductUnit.millilitre, label: l10n.productUnitMillilitre),
      if (showMeasuredGoods || value == ProductUnit.cup)
        SegmentedOption<ProductUnit>(
            value: ProductUnit.cup, label: l10n.productUnitCup),
    ];
    return SegmentedChoice<ProductUnit>(
      value: value,
      semanticLabel: l10n.productUnitPickerLabel,
      options: options,
      onChanged: onChanged,
    );
  }
}

String _sizeLabelOf(BuildContext context, ProductUnit unit) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return switch (unit) {
    ProductUnit.each => l10n.inventoryFieldSizeMl,
    ProductUnit.litre => l10n.productSizeLabelLitre,
    ProductUnit.millilitre => l10n.productSizeLabelMillilitre,
    ProductUnit.cup => l10n.productSizeLabelCup,
    // A tank's capacity, in the litres it holds once its kilograms have been
    // converted: the same field, read from the other side of the conversion.
    ProductUnit.kilogram => l10n.productSizeLabelKilogram,
  };
}

class _ProductEditor extends StatefulWidget {
  final Product? existing;
  final bool allowVariants;
  final ShopProfile shopProfile;
  final VoidCallback onSaved;
  const _ProductEditor({
    this.existing,
    required this.allowVariants,
    required this.shopProfile,
    required this.onSaved,
  });
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
  bool _persistedTrackVariants = false;

  bool _trackExpiry = false;

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
    final bottleMlText = e == null ? '' : e.bottleMl.toString();
    _bottleMl = TextEditingController(text: bottleMlText);
    _halfPrice = TextEditingController(text: _editAmount(e?.halfPrice));
    _quarterPrice = TextEditingController(text: _editAmount(e?.quarterPrice));
    _barcode = TextEditingController();
    _trackExpiry = e?.trackExpiry ?? false;
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

  Future<void> _loadMeta() async {
    final existing = widget.existing;
    if (existing?.id == null) {
      if (mounted) setState(() => _loadingMeta = false);
      return;
    }
    final productId = existing!.id!;
    final db = DatabaseHelper.instance;
    final flags = await VariantCatalogue.productFlags(productId);
    if (!widget.allowVariants) {
      // Non-Fashion profiles cannot create or edit variants, but an owner
      // moving a legacy catalogue between profiles must not lose the existing
      // flag or rows when they save an unrelated product field.
      if (mounted) {
        setState(() {
          _persistedTrackVariants = flags.trackVariants;
          _loadingMeta = false;
        });
      }
      return;
    }
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

  void _setTrackVariants(bool value) {
    setState(() {
      _trackVariants = value;
      if (value && _stock.text.trim().isEmpty) {
        final total = _drafts.fold<double>(0, (sum, d) => sum + d.stockQty);
        _stock.text = _editQuantity(total);
      }
    });
  }

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

  Product _draftParent() {
    final existing = widget.existing;
    double number(String text, double fallback) =>
        parseUserNumber(text) ?? fallback;
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
          parseUserCount(_reorder.text) ?? existing?.reorderLevel ?? 0,
      bottleMl: int.tryParse(_bottleMl.text.trim()) ?? existing?.bottleMl ?? 0,
      unit: _unit,
      trackVariants:
          widget.allowVariants ? _trackVariants : _persistedTrackVariants,
      trackExpiry: _trackExpiry,
      active: existing?.active ?? true,
      updatedAt: DateTime.now().toIso8601String(),
      remoteId: existing?.remoteId,
    );
  }

  Future<void> _flushPhoto(int productId, AppState state) async {
    final source = _pickedPhoto;
    final removed = _photoRemoved;
    if (source == null && !removed) return;

    final l10n = AppLocalizations.of(context);
    try {
      if (removed) {
        await ProductImageStore.delete(
          productId,
          workspaceKey: await WorkspaceService.activeWorkspaceKey(),
        );
        await DatabaseHelper.instance.setProductImage(null, productId);
      } else {
        final relative = await ProductImageStore.save(
          source!,
          productId: productId,
          workspaceKey: await WorkspaceService.activeWorkspaceKey(),
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

  Future<void> _removeVariant(int index) async {
    final draft = _drafts[index];
    if (!draft.isNew) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppLocalizations.of(dialogContext)
              .inventoryRemoveConfirm(draft.name)),
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

  Future<void> _saveVariants(int productId, {Transaction? txn}) async {
    final AppState state = context.read<AppState>();
    final db = DatabaseHelper.instance;
    final l10n = AppLocalizations.of(context);
    final savedIds = <int>[];
    Future<void> run(Transaction t) async {
      for (final removedId in _removedVariantIds) {
        // Also frees that variant's barcodes.
        await db.deleteVariantInTransaction(t, removedId);
      }
      for (var i = 0; i < _drafts.length; i++) {
        final draft = _drafts[i];
        // Position follows the order on screen, so reordering is reordering and
        // the till offers Dark before Regular because the owner put it there.
        final variantId = await db.upsertVariantInTransaction(
            t, draft.copyWith(position: i).toVariant(productId));
        savedIds.add(variantId);
      }
    }

    if (txn != null) {
      await run(txn);
    } else {
      final rawDb = await db.database;
      await rawDb.transaction(run);
    }
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

  Money? _optionalPrice(TextEditingController controller, String label) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final parsed = parseUserNumber(text);
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

    final cost = parseUserNumber(_cost.text);
    final price = parseUserNumber(_price.text);
    final stock = parseUserNumber(_stock.text);
    final reorder = parseUserCount(_reorder.text);
    final bottleMl = parseUserCount(_bottleMl.text);

    if (cost == null || price == null || stock == null) {
      setState(() => _error = cost == null
          ? AppLocalizations.of(context).inventoryCostPriceNotANumber
          : price == null
              ? AppLocalizations.of(context).inventorySellPriceNotANumber
              : AppLocalizations.of(context).inventoryStockNotANumber);
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
      // The shared validator answers with a code — the model layer cannot reach
      // `AppLocalizations` — and the editor shows the shop's language for it,
      // exactly as the imports screen does.
      setState(() => _error = ValidationUtils.productProblem(
          AppLocalizations.of(context), problem));
      return;
    }
    if (price < cost) {
      // The shared dialog, so the buttons and the dismissal case are handled
      // the same way everywhere. A tap outside the dialog is a DECISION NOT TO
      // SAVE, never a silent "save anyway".
      final AppLocalizations l10n = AppLocalizations.of(context);
      final ConfirmOutcome outcome = await confirmIrreversible(
        context,
        title: l10n.inventoryLowPriceTitle,
        message: l10n.inventoryLowPriceMessage(name, price, cost),
        confirmLabel: l10n.inventorySaveAnyway,
        cancelLabel: l10n.inventoryGoBack,
        // A warning, not a destruction: the owner is answering a question
        // about their own margin, and the button that carries the answer is
        // "Save anyway", not "Delete".
        isDestructive: false,
      );
      if (outcome is! ConfirmAccepted) return;
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
    if (_trackVariants && _drafts.isEmpty) {
      setState(
          () => _error = AppLocalizations.of(context).inventoryNoVariantsYet);
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
      bottleMl: bottleMl ?? 0,
      // Both read from the row rather than from the passed-in product, because
      // `Product.fromMap` leaves them at their defaults — writing them from a
      // product that came out of the database would switch off "sold as
      // variants" and reset the unit on every unrelated edit.
      unit: _unit,
      trackVariants: _trackVariants,
      trackExpiry: _trackExpiry,
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
      // Product and variants commit in one transaction: a variant save that
      // fails after the product insert must not leave a product the editor
      // still thinks is new, because the next Save would insert it again.
      final rawDb = await DatabaseHelper.instance.database;
      final productId = await rawDb.transaction((txn) async {
        final id = await DatabaseHelper.instance
            .upsertProductInTransaction(txn, product);
        if (widget.allowVariants) await _saveVariants(id, txn: txn);
        return id;
      });
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
      if (widget.allowVariants) await _saveVariants(productId);
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
      //
      // The module-level signal, so a save made from a screen pushed above the
      // shell reaches the till too.
      if (mounted) markCatalogueChanged();
      widget.onSaved();
      if (!mounted) return;
      // THE SAVE, CONFIRMED.
      //
      // A product save used to close the editor and say nothing. The owner
      // was left wondering whether it had saved, and a price that did not save
      // is a price the till keeps selling at. So the save ends on a screen
      // that says it worked and what it saved.
      //
      // The editor stays open UNDER the sheet, and the sheet's button closes
      // it — so the flow is Save, confirm, Done, and the list behind is
      // already refreshed.
      showOperationSuccess(
        context,
        title: widget.existing == null
            ? AppLocalizations.of(context).inventoryProductSavedTitle
            : AppLocalizations.of(context).inventoryProductUpdatedTitle,
        message: product.name,
        detailIcon: Icons.inventory_2_outlined,
      );
      if (!mounted) return;
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
        setState(
            () => _error = AppLocalizations.of(context).inventorySaveFailed);
      }
    }
  }

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

  /// The unit suffix to append to the stock/reorder labels so the person
  /// knows what they are entering — litres, millilitres, cups, kg, or items
  /// for a countable product.
  String _unitStockSuffix(AppLocalizations l10n, ProductUnit unit) {
    return switch (unit) {
      ProductUnit.each => l10n.unitSuffixEach,
      ProductUnit.litre => l10n.unitSuffixLitre,
      ProductUnit.millilitre => l10n.unitSuffixMillilitre,
      ProductUnit.cup => l10n.unitSuffixCup,
      ProductUnit.kilogram => l10n.unitSuffixKilogram,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(userNumberPattern),
                    ])),
                SizedBox(width: spacing.md),
                Expanded(
                    child: TextField(
                        controller: _price,
                        decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)
                                .inventoryFieldSellPrice),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(userNumberPattern),
                    ])),
              ]),
              SizedBox(height: spacing.md),
              // What the product is measured in, and the one control this form
              // has never had. `_unit` was read from the row and written back
              // unchanged, so a product created HERE was always `each` — and a
              // shop with plenty of stock could then not pour a single shot cup,
              // because "pour from" only offers volumetric drinks. Every shot
              // cup, every litre of beer and every tank depends on this.
              _UnitPicker(
                value: _unit,
                showMeasuredGoods: context
                    .read<AppState>()
                    .shopProfile
                    .navigation
                    .showMeasuredGoods,
                onChanged: (ProductUnit unit) => setState(() => _unit = unit),
              ),
              SizedBox(height: spacing.md),
              if (widget.shopProfile.navigation.showDrinkService)
                TextField(
                  controller: _bottleMl,
                  decoration: InputDecoration(
                      labelText: _sizeLabelOf(context, _unit),
                      helperText: AppLocalizations.of(context)
                          .inventoryFieldSizeMlHelper),
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(userDigitsPattern),
                  ]),
              // The one thing a cup product needs to be told: it is poured from
              // something bigger, and where. Without this the next screen is a
              // dead end, which is exactly how this used to read.
              if (_unit == ProductUnit.cup)
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: spacing.md,
                    end: spacing.md,
                    top: spacing.xs,
                  ),
                  child: Text(
                    AppLocalizations.of(context).productUnitCupPourHint,
                    style: AppTypography.of(context)
                        .bodySmall
                        ?.copyWith(color: AppColors.of(context).onSurfaceMuted),
                  ),
                ),
              if (_visibleSizeSuggestions.isNotEmpty) _sizeSuggestionChips(),
              if (widget.shopProfile.navigation.showDrinkService)
                Row(children: [
                  Expanded(
                    child: TextField(
                        controller: _halfPrice,
                        decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)
                                .inventoryFieldHalfPriceOptional,
                            helperText: AppLocalizations.of(context)
                                .inventoryFieldHalfPriceHelper),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(userNumberPattern),
                    ])),
                SizedBox(width: spacing.md),
                Expanded(
                    child: TextField(
                        controller: _quarterPrice,
                        decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)
                                .inventoryFieldQuarterPriceOptional,
                            helperText: AppLocalizations.of(context)
                                .inventoryFieldQuarterPriceHelper),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(userNumberPattern),
                    ])),
              ]),
              SizedBox(height: spacing.md),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _stock,
                        decoration: InputDecoration(
                            labelText: _trackVariants
                                ? l10n.inventoryFieldTotalStock
                                : _unit == ProductUnit.each
                                    ? l10n.inventoryFieldStockQty
                                    : l10n.inventoryFieldStockQtyUnit(
                                        _unitStockSuffix(l10n, _unit)),
                            helperText: _trackVariants
                                ? l10n.inventoryStockIsDerived
                                : null),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(userNumberPattern),
                    ])),
                SizedBox(width: spacing.md),
                Expanded(
                    child: TextField(
                        controller: _reorder,
                        decoration: InputDecoration(
                            labelText: _unit == ProductUnit.each
                                ? l10n.inventoryFieldReorderLevel
                                : l10n.inventoryFieldReorderLevelUnit(
                                    _unitStockSuffix(l10n, _unit))),
                        keyboardType: TextInputType.numberWithOptions(
                            decimal: _unit != ProductUnit.each),
                        inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(
                          _unit == ProductUnit.each
                              ? userDigitsPattern
                              : userNumberPattern),
                    ])),
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
              if (widget.allowVariants)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _trackVariants,
                  onChanged: _setTrackVariants,
                  title: Text(
                      AppLocalizations.of(context).inventorySoldAsVariants),
                  // Says what turning it on does to the till, because the switch
                  // is otherwise invisible in its consequences: with it on, the
                  // product itself stops being sellable and its variants take over.
                  subtitle: Text(_trackVariants
                      ? AppLocalizations.of(context)
                          .inventorySoldAsVariantsOnSubtitle
                      : AppLocalizations.of(context)
                          .inventorySoldAsVariantsOffSubtitle),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _trackExpiry,
                onChanged: (value) => setState(() => _trackExpiry = value),
                title: const Text('Track expiry dates'),
                subtitle: Text(_trackExpiry
                    ? 'Received stock needs an expiry date and sells oldest first.'
                    : 'Stock is not separated by expiry date.'),
              ),
              if (widget.allowVariants && _trackVariants) ...[
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
        decoration:
            InputDecoration(labelText: l10n.inventoryLowStockLimitTitle),
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

class _StockCountBadge extends StatelessWidget {
  const _StockCountBadge({required this.quantity, required this.tone});

  final int quantity;

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
