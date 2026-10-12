import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import '../routing/routes.dart';
import '../models/audit_log.dart';
import '../services/app_state.dart';
import '../services/audit_actor.dart';
import '../services/backend_service.dart';
import '../services/barcode/barcode_service.dart';
import '../services/barcode/scan_input_service.dart';
import '../services/etims/etims_service.dart';
import '../services/printer/printer_config.dart';
import '../services/printer/receipt_printer.dart';
import '../widgets/sign_out_sheet.dart';
import '../routing/home_shell.dart';
import '../widgets/variant_catalogue.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/layout/page.dart';
import '../ui/components/surface.dart';
import '../models/models.dart';
import '../db/database_helper.dart';
import '../utils/money.dart';
import '../utils/units.dart';

class SellScreen extends StatefulWidget {
  const SellScreen({super.key});

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  static const _pollTimeout = Duration(seconds: 20);
  final List<CartItem> _cart = [];
  final Map<int, double> _reservedByProduct = <int, double>{};
  final Map<int, double> _reservedByVariant = <int, double>{};

  /// The shell's catalogue-change signal. Assigned in `initState`.
  late final HomeShellTabs _shellTabs;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _wedge = WedgeScannerBuffer();

  /// Holds the screen-level key listener.
  ///
  /// Autofocused on mount (see the `KeyboardListener` below) and not
  /// traversable: a wedge scanner types into whatever has focus, so this node
  /// holds focus in the idle state precisely so the screen sees the keys.
  final _wedgeFocus = FocusNode(skipTraversal: true);
  List<Product> _products = [];

  /// Which products are sold as variants, and what those variants are.
  ///
  /// Loaded with the products, not per tile: a till asks the same two questions
  /// about every product it draws, and a query per grid cell is a grid that
  /// stutters exactly when the shop is busiest.
  VariantCatalogue _variants = VariantCatalogue.empty;

  /// Fixed shot cups available at this till, for products still in the
  /// catalogue.
  ///
  /// Loaded with the products rather than per tile, for the same reason: a shot
  /// lookup per grid cell is a query per cell, and the till asks it about every
  /// product it draws.
  List<ShotCup> _shots = const [];

  String _searchQuery = '';
  bool _loading = true;
  bool _processingPayment = false;
  bool _portionSheetOpen = false;
  bool _scanInFlight = false;
  String? _statusMessage;

  /// Whether the search field currently holds focus, mirrored into state.
  ///
  /// Tracked rather than read from `FocusManager` at key time because the
  /// focus listener fires *after* the key event that changed it, so the wedge
  /// handler would still see the stale value for one keystroke.
  bool _searchHasFocus = false;

  void _announceStatus(String message) {
    if (!mounted) return;
    setState(() => _statusMessage = message);
    unawaited(SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    ));
  }

  @override
  void initState() {
    super.initState();
    // The shell keeps this screen alive across tab switches, so it reloads when
    // the catalogue is written to rather than only when it is first shown.
    _shellTabs = context.read<HomeShellTabs>();
    _shellTabs.addListener(_onShellChanged);
    _searchFocus.addListener(() {
      // The wedge buffer is disarmed while the search field holds focus, so a
      // human typing a product name can never be read as a scan. Tracked as
      // state rather than read from `FocusManager` at key time because the
      // listener fires *after* the key event that cleared it.
      final focused = _searchFocus.hasFocus;
      if (focused == _searchHasFocus) return;
      setState(() {
        _searchHasFocus = focused;
        if (focused) _wedge.reset();
      });
    });
    _loadProducts();
  }

  int _seenCatalogueGeneration = 0;

  void _onShellChanged() {
    final generation = _shellTabs.catalogueGeneration;
    if (generation == _seenCatalogueGeneration) return;
    _seenCatalogueGeneration = generation;
    _loadProducts();
  }

  @override
  void dispose() {
    _shellTabs.removeListener(_onShellChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _wedgeFocus.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final db = DatabaseHelper.instance;
    final results = await Future.wait([
      db.getProducts(),
      VariantCatalogue.load(),
      db.getShotCups(),
    ]);
    final products = results[0] as List<Product>;
    final catalogue = results[1] as VariantCatalogue;
    final cups = results[2] as List<ShotCup>;
    final liveIds = products.where((p) => p.active).map((p) => p.id).toSet();
    final shots = cups.where((c) => liveIds.contains(c.productId)).toList();
    if (mounted) {
      setState(() {
        _products = products.where((p) => p.active).toList();
        _variants = catalogue;
        _shots = shots;
        _loading = false;
      });
    }
  }

  /// The cups configured against [product], in the order they were set up.
  List<ShotCup> _shotsFor(Product product) =>
      _shots.where((c) => c.productId == product.id).toList();

  /// Bottle units already reserved in the cart for this product, across all
  /// portions. Portion availability must subtract this, otherwise a cashier can
  /// fill the cart with more product than exists and the sale only fails at
  /// `recordSale` — after the customer has already paid.
  ///
  /// Variant lines are skipped: they reserve their own variant's stock, which is
  /// a different pile of bottles, and counting them here would let a Dark order
  /// eat into the Regular stock.
  double _cartUnitsFor(Product product) =>
      _reservedByProduct[product.id] ?? 0.0;

  /// Units of one variant already reserved in the cart.
  double _cartUnitsForVariant(ProductVariant variant) =>
      _reservedByVariant[variant.id] ?? 0.0;

  void _rebuildReservations() {
    _reservedByProduct.clear();
    _reservedByVariant.clear();
    for (final line in _cart) {
      final variant = line.variant;
      if (variant != null && variant.id != null) {
        _reservedByVariant[variant.id!] =
            (_reservedByVariant[variant.id] ?? 0.0) + line.qty;
      } else if (line.shotCup != null) {
        final fraction = line.product.bottleMl <= 0
            ? 1.0
            : (line.shotCup!.capacityMl / line.product.bottleMl)
                .clamp(0.0, 1.0);
        if (line.product.id != null) {
          _reservedByProduct[line.product.id!] =
              (_reservedByProduct[line.product.id] ?? 0.0) +
                  line.qty * fraction;
        }
      } else {
        if (line.product.id != null) {
          _reservedByProduct[line.product.id!] =
              (_reservedByProduct[line.product.id] ?? 0.0) +
                  line.qty * line.product.fractionFor(line.portion);
        }
      }
    }
  }

  /// Offers a safe way out of an outstanding M-Pesa push.
  ///
  /// The guard must not be a dead end: a till that cannot reconcile is a till
  /// that cannot take cash-equivalent payments. Re-querying the provider is the
  /// only safe action — it never re-pushes, so it cannot double-charge. A
  /// definitive FAILED clears the row; SUCCESS books the saved basket from the
  /// durable `cart_json` snapshot; anything else keeps the block in place.
  Future<void> _reconcileOutstandingPayment(
      Map<String, dynamic> pending) async {
    final reference = pending['reference'] as String? ?? '';
    if (reference.isEmpty) {
      await DatabaseHelper.instance.resolvePendingPayment(reference);
      return;
    }

    final amount = pending['amount'];
    _announceStatus('Checking payment $reference…');
    // A reconcile is a status check, not a fresh purchase, so it gets a short
    // budget and visible progress rather than the 90s the sale flow uses. The
    // operator is told to try again if it is still unconfirmed.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator()),
            const SizedBox(width: 16),
            Expanded(
                child: Text(AppLocalizations.of(context)
                    .sellCheckingPayment(reference))),
          ],
        ),
      ),
    );
    final outcome = await BackendService.pollPaymentStatus(reference,
        timeout: _pollTimeout);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (outcome == PaymentOutcome.failed) {
      // Definitively declined: the basket was never charged, so dropping the
      // row is safe and unblocks the till.
      await DatabaseHelper.instance.resolvePendingPayment(reference);
      if (!mounted) return;
      _announceStatus('Payment $reference was declined. You can retry.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(AppLocalizations.of(context).sellReferenceDeclined(reference)),
      ));
      return;
    }

    if (outcome == PaymentOutcome.success) {
      final recorded = await _recordReconciledSale(pending);
      if (!mounted) return;
      if (recorded) {
        setState(() {
          _cart.clear();
          _rebuildReservations();
        });
        _loadProducts();
      }
      return;
    }

    _announceStatus(
        'Payment $reference is still unconfirmed. Do not charge again.');
    final checkAgain = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).sellPaymentUnconfirmedTitle),
        content: Text(
            'Reference $reference${amount is num ? ' for ${formatMoney(Money.fromMajor(amount))}' : ''} has not been confirmed by the provider. '
            'Do not charge the customer again. Check again now, or record the sale later from Reports.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context).sellCheckAgainLater),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context).sellCheckAgainAction),
          ),
        ],
      ),
    );
    if (checkAgain == true && mounted) {
      await _reconcileOutstandingPayment(pending);
    }
  }

  /// Books the basket saved on an outstanding payment row.
  ///
  /// Uses the persisted `cart_json` rather than the live cart, because the
  /// customer's basket belongs to the original push and must not be mutated by
  /// whatever the cashier has typed since.
  Future<bool> _recordReconciledSale(Map<String, dynamic> pending) async {
    // Read before the first await: the audit row written after the sale is
    // attributed from the session, and a BuildContext must not be held across
    // an await.
    final AppState state = context.read<AppState>();
    final reference = pending['reference'] as String? ?? '';
    // The row is the only record that this payment still needs booking. If it
    // has already gone — a concurrent reconcile, or the stale sweep — booking
    // it here would write the same sale to the ledger a second time.
    if (!await DatabaseHelper.instance.hasPendingPayment(reference)) {
      _announceStatus('Reference $reference was already reconciled.');
      return false;
    }
    try {
      final decoded = jsonDecode(pending['cart_json'] as String? ?? '[]');
      if (decoded is! List) return false;
      final items = <SaleItem>[];
      // Units per variant, so the variant's own stock moves too. The names in
      // the snapshot are already folded, so nothing here needs the variant
      // itself — only the count, which is what stock is.
      final variantUnits = <int, double>{};
      for (final line in decoded) {
        if (line is! Map) continue;
        items.add(SaleItem(
          saleId: 0,
          productId: (line['productId'] as num?)?.toInt() ?? 0,
          productName: line['productName'] as String? ?? '',
          qty: (line['qty'] as num?)?.toDouble() ?? 0,
          unitPrice: Money.fromMinor((line['unitPrice'] as num?)?.toInt() ?? 0),
          unitCost: Money.fromMinor((line['unitCost'] as num?)?.toInt() ?? 0),
          portion: line['portion'] as String? ?? 'full',
          portionMl: (line['portionMl'] as num?)?.toInt() ?? 0,
        ));
        final variantId = (line['variantId'] as num?)?.toInt();
        if (variantId != null) {
          variantUnits[variantId] = (variantUnits[variantId] ?? 0) +
              ((line['qty'] as num?)?.toDouble() ?? 0);
        }
      }
      if (items.isEmpty) return false;
      await DatabaseHelper.instance.recordSale(
        staffName: pending['staff_name'] as String? ?? 'Unknown',
        staffId: (pending['staff_id'] as num?)?.toInt(),
        items: items,
        // The provider confirmed the money, so authoritative stock already
        // moved server-side. Keep the local ledger consistent regardless of
        // any cached drift.
        enforceStock: false,
        paymentMethod: 'mpesa',
        paymentReference: reference,
      );
      // A reconciled payment is a sale the till never saw happen — the money
      // arrived from the provider, not from a cart on screen. That is precisely
      // the sale an audit log exists to explain.
      await recordActionAudit(
        state,
        action: AuditAction.saleRecorded,
        entity: AuditEntity.sale,
        entityId: reference,
        detail: '${items.length} line(s), M-Pesa, reconciled',
      );
      for (final entry in variantUnits.entries) {
        try {
          await VariantCatalogue.deductVariantStock(entry.key, entry.value);
        } catch (_) {
          // The sale is booked; a variant count to correct at the next stock
          // take is not worth failing a reconciliation over.
        }
      }
      await DatabaseHelper.instance.resolvePendingPayment(reference);
      _announceStatus('Reconciled payment $reference and recorded the sale.');
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          AppLocalizations.of(context)
              .sellPaymentReceivedSaleRecorded(reference),
        ),
      ));
      return true;
    } catch (_) {
      // The row must survive: the money is confirmed but the local ledger is
      // not, and dropping the row would lose the only copy of the basket.
      _announceStatus(
          'Payment $reference was received but needs manual repair.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Payment $reference was received but could not be recorded locally. Keep this reference and contact support.'),
        ));
      }
      return false;
    }
  }

  /// Handles a code that arrived from a wedge scanner or the camera.
  ///
  /// Both sources funnel through here so a product added by scan is
  /// indistinguishable from one added by tapping the tile — same portion
  /// default, same stock re-validation, same merge into an existing line.
  ///
  /// Resolved through `getScanTarget` rather than by barcode alone, because a
  /// code can belong to the product *or* to one of its variants and the two sell
  /// differently: a variant's code must add that variant, at the variant's price,
  /// out of the variant's stock. Resolving to the product and stopping there is
  /// how "Dark" quietly gets charged at the parent's price.
  Future<void> _handleScan(ScanResult scan) async {
    if (_scanInFlight) return;
    _scanInFlight = true;
    try {
      final target =
          await DatabaseHelper.instance.getScanTarget(scan.normalised);
      if (!mounted) return;
      if (target == null) {
        final problem = Barcode.rejectionReason(scan.normalised);
        // Names the variant case in the same message, because a code that was
        // never attached to anything is usually a code the owner typed into the
        // wrong field — a variant's code belongs on that variant.
        final message =
            problem ?? AppLocalizations.of(context).sellScanNoProductBarcode;
        _announceStatus(message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      final product = target.product;
      final variant = target.variant;
      if (variant == null && _variants.sellsAsVariants(product)) {
        // The product's own code on a product that is only sellable as one of
        // its variants. Refused out loud: adding the parent here would charge
        // the parent's price for something the owner never priced, and the
        // cashier would only find out at the stock count.
        final message = AppLocalizations.of(context)
            .sellScanVariantOnlyMessage(product.name);
        _announceStatus(message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      if (variant != null && variant.stockQty <= 0) {
        final message = AppLocalizations.of(context)
            .sellScanVariantOutOfStockMessage(variant.label);
        _announceStatus(message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      // A scan is a whole unit of whatever it resolved to. A sheet of choices
      // would cost one modal per label, which is unusable at a till; a half or
      // a different size is changed on the cart line instead.
      await _addToCartDirect(product, 'full', variant: variant);
    } finally {
      _scanInFlight = false;
    }
  }

  /// Screen-level key handler for hardware wedge scanners.
  ///
  /// A `KeyboardListener` rather than autofocus on a hidden field: autofocus
  /// pops the soft keyboard over the cart, which is a worse problem than the
  /// one being solved. The listener sees every key the till receives while no
  /// field has focus and ignores everything while the search field does.
  void _onKeyEvent(KeyEvent event) {
    if (_searchHasFocus || _portionSheetOpen || _processingPayment) {
      _wedge.reset();
      return;
    }
    final scan = _wedge.onKey(event);
    if (scan == null) return;
    unawaited(_handleScan(scan));
  }

  Future<void> _scanWithCamera() async {
    // `push`, not `go`: the scanner is a screen the user comes back FROM with a
    // result, and `go` would replace the till in the shell's branch history.
    // The camera surface itself is deliberately a ROUTE rather than a pushed
    // `Navigator` page, so deep linking can reach it and the back button from
    // inside the viewfinder leaves the till.
    try {
      final GoRouter router = GoRouter.of(context);
      final ScanResult? scan = await router.push<ScanResult>(Routes.cameraScan);
      // A null result is the user backing out, which is its own outcome and not a
      // failed scan. There is nothing to add to the cart.
      if (scan == null) return;
      await _handleScan(scan);
    } catch (e) {
      if (!mounted) return;
      // The message names what to do NEXT, not what broke: a cashier mid-sale
      // with a queue behind them needs the wedge scanner or the product list,
      // not a stack trace. The wedge path is mentioned because it is the
      // fallback that never needs the camera at all.
      final l10n = AppLocalizations.of(context);
      _announceStatus(l10n.sellScanCameraError);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sellScanCameraError)),
      );
    }
  }

  Future<void> _addToCart(Product product) async {
    // Re-entrancy guard. `_addToCart` is async and opens a modal; a fast
    // double-tap on a product tile, or a wedge scan landing mid-sheet, would
    // otherwise stack two sheets on top of each other.
    if (_portionSheetOpen) return;
    _portionSheetOpen = true;
    final variants = _variants.of(product);
    final sellsAsVariants = _variants.sellsAsVariants(product);
    final shots = _shotsFor(product);
    String? choice;
    try {
      choice = await showModalBottomSheet<String>(
        context: context,
        builder: (sheetContext) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  AppLocalizations.of(context)
                      .sellChooseServingTitle(product.name),
                  style: Theme.of(context).textTheme.titleMedium)),
          if (sellsAsVariants && variants.isEmpty)
            // Said rather than silently offering full/half/quarter: on a
            // variant product those portions are the parent's, and charging
            // them for "Dark" is a price nobody set.
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(AppLocalizations.of(context)
                  .sellNoVariantsYetTitle(product.name)),
              subtitle: Text(
                AppLocalizations.of(context).sellNoVariantsYetHint,
              ),
              enabled: false,
            )
          else if (sellsAsVariants)
            // The variants replace the portions rather than joining them: a
            // half of "Dark" is not something the shop sells, and offering both
            // would put eight rows on a phone screen.
            for (final variant in variants)
              _variantOption(sheetContext, variant)
          else ...[
            _portionOption(
                sheetContext, product, 'full', 'Full', product.sellPrice),
            _portionOption(sheetContext, product, 'half', 'Half',
                product.priceFor('half')),
            _portionOption(sheetContext, product, 'quarter', 'Quarter',
                product.priceFor('quarter')),
          ],
          // Shots sit under the portions rather than replacing them: a bar sells
          // a whole bottle *and* shots of the same spirit, and a sheet that
          // offered one or the other would hide half the shelf.
          if (shots.isNotEmpty) ...[
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(AppLocalizations.of(context).sellShotsSection,
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            for (final cup in shots) _shotOption(sheetContext, product, cup),
          ],
        ])),
      );
    } finally {
      _portionSheetOpen = false;
    }
    if (choice == null || !mounted) return;
    if (choice.startsWith(_shotChoicePrefix)) {
      final cupId = int.tryParse(choice.substring(_shotChoicePrefix.length));
      final cup = _shots.where((c) => c.id == cupId).firstOrNull;
      if (cup == null) {
        // The cup was removed while the sheet was open. Say so rather than
        // falling back to the whole bottle, which would charge full price for a
        // shot.
        _say('That shot cup is no longer available. Try again.');
        return;
      }
      await _addToCartDirect(product, SalePortion.measured, shotCup: cup);
      return;
    }
    if (choice.startsWith(_variantChoicePrefix)) {
      final variant = _variants
          .byId(int.tryParse(choice.substring(_variantChoicePrefix.length)));
      if (variant == null) {
        // The variant was deleted while the sheet was open. Say so rather than
        // falling back to the parent.
        _say('That variant is no longer on ${product.name}. Try again.');
        return;
      }
      await _addToCartDirect(product, 'full', variant: variant);
      return;
    }
    await _addToCartDirect(product, choice);
  }

  /// Marker for a variant choice in the sheet's result.
  ///
  /// A prefix rather than a second return value, because the sheet already
  /// returns "what did they tap" as one string and the variant id needs saying
  /// alongside it without changing what every other caller passes back.
  static const String _variantChoicePrefix = 'v:';

  /// A quantity the way the owner reads it: no trailing `.0` on a whole number.
  static String _qtyLabel(double qty) =>
      qty % 1 == 0 ? qty.toInt().toString() : '$qty';

  /// Announces and shows one message. Both, every time: the announcement is for
  /// a screen reader and the snack bar for everyone looking at the cart.
  void _say(String message) {
    _announceStatus(message);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Adds one unit of [product] in [portion] with no modal in the way.
  ///
  /// The scan path uses this, and it *shares* the stock re-validation and merge
  /// logic with [_addToCart] rather than repeating it. Duplicating that check
  /// is exactly how the oversell-after-payment bug comes back: the cart would
  /// look right, `recordSale` would then throw after the customer had paid.
  ///
  /// [variant] is set when the line is one variant of the product. Its price,
  /// cost and stock are its own: a variant is a whole unit of itself, so the
  /// portion arithmetic — halves, quarters, fractions of a bottle — does not
  /// apply to it at all.
  ///
  /// Portion changes are made on the cart line afterwards, so a scanner never
  /// costs throughput — one scan is one tap, not a modal.
  Future<void> _addToCartDirect(Product product, String portion,
      {ProductVariant? variant, ShotCup? shotCup}) async {
    // Re-check against the loaded product rather than the caller's snapshot:
    // the tap and the resolution are separated by a frame, and stock moves.
    final current = _products.where((p) => p.id == product.id).firstOrNull;
    if (current == null) return;
    if (variant != null) {
      // The variant's own count, not the parent's. The parent's is the sum of
      // its variants for a variant product, so checking it here would let two
      // orders of Dark go through while Regular is the only one in stock.
      final available = variant.stockQty - _cartUnitsForVariant(variant);
      if (available < 1) {
        _say(available <= 0
            ? 'All ${variant.name} stock is already in the cart.'
            : 'No ${variant.name} left. Adjust the cart before adding more.');
        return;
      }
      // Merges on the variant, not on the product: Dark and Regular are two
      // lines, and combining them would charge the first one's price for both.
      final existing = _cart.where((c) => c.variant?.id == variant.id);
      setState(() {
        if (existing.isNotEmpty) {
          existing.first.qty++;
        } else {
          _cart.add(CartItem(
              product: current, portion: 'full', qty: 1, variant: variant));
        }
        _rebuildReservations();
      });
      return;
    }
    if (shotCup != null) {
      // A shot comes out of the parent bottle, so it is checked and reserved
      // against the parent — not against a count of its own, which it has none
      // of. The amount reserved is the poured volume as a fraction of the
      // bottle, so twenty-five shots of a 750 ml spirit are one bottle.
      final needed = shotCup.capacityMl <= 0 || current.bottleMl <= 0
          ? 1.0
          : (shotCup.capacityMl / current.bottleMl).clamp(0.0, 1.0);
      final available = current.stockQty - _cartUnitsFor(current);
      if (available < needed) {
        _say('Not enough ${current.name} left for another shot. '
            'Adjust the cart before adding more.');
        return;
      }
      // Merges on the cup, not on the product: a 30 ml shot and a 45 ml shot of
      // the same spirit are two lines at two prices, and combining them would
      // charge the first one's price for both.
      final existing = _cart.where((c) => c.shotCup?.id == shotCup.id);
      setState(() {
        if (existing.isNotEmpty) {
          existing.first.qty++;
        } else {
          _cart.add(CartItem(
            product: current,
            portion: SalePortion.measured,
            qty: 1,
            shotCup: shotCup,
          ));
        }
        _rebuildReservations();
      });
      return;
    }
    final needed = current.fractionFor(portion);
    if (current.stockQty - _cartUnitsFor(current) < needed) {
      _say('Not enough ${current.name} left. '
          'Adjust the cart before adding more.');
      return;
    }
    final existing = _cart.where((c) =>
        c.variant == null &&
        c.shotCup == null &&
        c.product.id == current.id &&
        c.portion == portion);
    setState(() {
      if (existing.isNotEmpty) {
        existing.first.qty++;
      } else {
        _cart.add(CartItem(product: current, portion: portion, qty: 1));
      }
      _rebuildReservations();
    });
  }

  Widget _portionOption(BuildContext context, Product product, String portion,
      String label, Money price) {
    final needed = product.fractionFor(portion);
    final available = product.stockQty - _cartUnitsFor(product);
    final canAdd = available >= needed;
    return ListTile(
      leading: const Icon(Icons.local_bar_outlined),
      title: Text(
        AppLocalizations.of(context)
            .sellPourOptionTitle(label, '${product.mlFor(portion)}'),
      ),
      trailing: Text(formatMoney(price)),
      enabled: canAdd,
      subtitle: !canAdd
          ? Text(available <= 0
              ? 'All stock for this product is already in the cart'
              : 'Only $available of a bottle left')
          : null,
      onTap: canAdd ? () => Navigator.pop(context, portion) : null,
    );
  }

  /// One shot cup in the portion sheet: a fixed capacity of [product] at the
  /// cup's own price.
  ///
  /// How many are left is stated in bottles rather than in shots, because that is
  /// what the stock figure is and what the next customer can actually be served.
  /// A capacity larger than the bottle reads as one bottle available, which is
  /// the honest answer to a cup that cannot be poured from what is in stock.
  Widget _shotOption(BuildContext sheetContext, Product product, ShotCup cup) {
    final verdict = shotAvailability(product, cup, product.stockQty);
    return ListTile(
      leading: Icon(verdict.canPour
          ? Icons.local_drink_outlined
          : Icons.warning_amber_outlined),
      title: Text(
        AppLocalizations.of(context)
            .sellPourOptionTitle(cup.label, '${cup.capacityMl}'),
      ),
      trailing: Text(formatMoney(cup.price)),
      enabled: verdict.canPour,
      // Each blocked reason names its own cause. "Not available" would leave a
      // cashier guessing, and the causes need different fixes: add stock, count
      // the drawer down, or change the cup.
      subtitle: Text(verdict.reason),
      onTap: verdict.canPour
          ? () => Navigator.pop(sheetContext, '$_shotChoicePrefix${cup.id}')
          : null,
    );
  }

  /// Marker for a shot-cup choice in the sheet's result. See
  /// [_variantChoicePrefix] for why this is a prefix rather than a second value.
  static const String _shotChoicePrefix = 's:';

  /// One variant in the portion sheet, at its own price and from its own stock.
  ///
  /// The low-stock warning rides on the icon *and* the words, never on colour
  /// alone: "low stock" in the subtitle is what a cashier reads at speed, and it
  /// is what a screen reader announces.
  Widget _variantOption(BuildContext sheetContext, ProductVariant variant) {
    final available = variant.stockQty - _cartUnitsForVariant(variant);
    final canAdd = available >= 1;
    return ListTile(
      leading: Icon(variant.isLow
          ? Icons.warning_amber_outlined
          : Icons.local_bar_outlined),
      title: Text(variant.label),
      trailing: Text(formatMoney(variant.sellPrice)),
      enabled: canAdd,
      subtitle: Text(!canAdd
          ? (available <= 0
              ? 'All stock is already in the cart'
              : 'No stock left')
          : (variant.isLow
              ? '${_qtyLabel(variant.stockQty)} in stock · low'
              : '${_qtyLabel(variant.stockQty)} in stock')),
      onTap: canAdd
          ? () =>
              Navigator.pop(sheetContext, '$_variantChoicePrefix${variant.id}')
          : null,
    );
  }

  void _updateQty(int index, double delta) {
    setState(() {
      _cart[index].qty = (_cart[index].qty + delta).clamp(0, 999).toDouble();
      if (_cart[index].qty == 0) _cart.removeAt(index);
      _rebuildReservations();
    });
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
      _rebuildReservations();
    });
  }

  /// Summing integer cents, the same way [DatabaseHelper.recordSale] does, so the
  /// figure on screen is exactly the figure written to the ledger.
  Money get _total => sumMoney(_cart.map((item) => item.total));

  static const _offlinePaymentLabels = <String, String>{
    'cash': 'Cash',
    'card': 'Card',
    'bank_transfer': 'Bank transfer',
    'mobile_money_manual': 'Mobile money (manual)',
  };

  /// The ledger line for one cart row.
  ///
  /// `SaleItem` lives in a file this feature may not edit and has nowhere to put
  /// a variant, so the variant is folded into [SaleItem.productName] here, at
  /// the point the line is built. That is also the only place it *can* be
  /// folded: the name is what the receipt prints and what the ledger stores, so
  /// a line that reads "Kenyana Beer · Dark" still says Dark after the owner
  /// renames or deletes the variant — the only thing a receipt the customer was
  /// already handed can do.
  SaleItem _saleItemFor(CartItem line) => SaleItem(
        saleId: 0,
        productId: line.product.id!,
        productName: line.foldedName,
        qty: line.qty,
        unitPrice: line.unitPrice,
        unitCost: line.unitCost,
        portion: line.portion,
        // A variant's own serving size, not a fraction of the parent's bottle:
        // "Dark 500 ml" is 500ml however big the parent bottle is. A shot's is
        // its cup's fixed capacity, which is the same idea.
        portionMl: line.portionMl,
      );

  /// Takes the sold quantity off each variant's own stock, once the sale is
  /// committed.
  ///
  /// `recordSale` checks and decrements `products.stock_qty` and knows nothing
  /// about `product_variants`, so without this the variant's count would never
  /// move and the till would sell Dark until the stock take found out. The
  /// parent's aggregate is refreshed by the same call, so the ledger's own check
  /// keeps agreeing with what the variants hold.
  ///
  /// Best effort by design: the sale is already committed and the money already
  /// taken, so a failure here is a stock count to correct at the next stock
  /// take — never a reason to fail a checkout that happened.
  Future<void> _deductVariantStockForSale(Iterable<CartItem> lines) async {
    final sold = <int, double>{};
    for (final line in lines) {
      final id = line.variant?.id;
      if (id == null) continue;
      sold[id] = (sold[id] ?? 0) + line.qty;
    }
    for (final entry in sold.entries) {
      try {
        await VariantCatalogue.deductVariantStock(entry.key, entry.value);
      } catch (_) {
        // Deliberately swallowed — see above. The next stock adjustment or
        // reload reconciles the count.
      }
    }
  }

  Future<void> _checkoutOffline() async {
    if (_cart.isEmpty || _processingPayment) return;
    final amountController =
        TextEditingController(text: _total.asMajor.toStringAsFixed(2));
    final referenceController = TextEditingController();
    var method = 'cash';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).sellOfflinePaymentTitle),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              AppLocalizations.of(context)
                  .sellSaleTotalLabel(formatMoney(_total)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: method,
              decoration: InputDecoration(
                  labelText:
                      AppLocalizations.of(context).sellPaymentMethodLabel),
              items: _offlinePaymentLabels.entries
                  .map((entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) setDialogState(() => method = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              decoration: InputDecoration(
                labelText:
                    method == 'cash' ? 'Amount received' : 'Amount confirmed',
                prefixText: 'KSh ',
                helperText: method == 'cash'
                    ? 'Extra amount is recorded as change.'
                    : 'Must match the sale total.',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: referenceController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).sellReferenceLabel,
              ),
              textInputAction: TextInputAction.done,
            ),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(AppLocalizations.of(context).actionCancel)),
            FilledButton(
              onPressed: () {
                final typed = double.tryParse(amountController.text.trim());
                final amount = typed == null ? null : Money.fromMajor(typed);
                if (amount == null ||
                    amount < _total ||
                    (method != 'cash' &&
                        (amount - _total).minorUnits.abs() > 1)) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                    content: Text(method == 'cash'
                        ? 'Amount received must be at least ${formatMoney(_total)}.'
                        : 'Amount confirmed must equal ${formatMoney(_total)}.'),
                  ));
                  return;
                }
                Navigator.pop(dialogContext, {
                  'method': method,
                  'amount': amount.minorUnits.toString(),
                  'reference': referenceController.text.trim(),
                });
              },
              child: Text(AppLocalizations.of(context).sellRecordSaleAction),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    referenceController.dispose();
    if (result == null || !mounted) return;
    await _checkout(
      result['method']!,
      amountTendered: Money.fromMinor(int.parse(result['amount']!)),
      paymentReference:
          result['reference']!.isEmpty ? null : result['reference'],
    );
  }

  Future<void> _checkout(
    String paymentMethod, {
    required Money amountTendered,
    String? paymentReference,
  }) async {
    if (_cart.isEmpty || _processingPayment) return;

    final state = context.read<AppState>();

    // Resolved once, before the sale is written, so the queue decision and the
    // post-sale flush cannot disagree about whether this sale owes KRA a
    // receipt.
    final etimsEnabled = await EtimsService().isEnabledForSales();

    // Resolve the signed-in person's id so the sale carries a stable
    // `staff_id`. Ledger attribution is keyed on that id, not the display
    // name, so cash sales must record it too or cashier deletion silently
    // leaves the real name on the ledger.
    //
    // An owner who opened a shift has an id (signInAsOwner(staffId:)), and
    // `expectedCashForShift` scopes by that id — so owner cash sales must
    // record it too, or they vanish from the till reconciliation. The name
    // lookup below is only a fallback for rows whose id was never set.
    int? staffId = state.currentStaffId;
    if (staffId == null) {
      final staff = await DatabaseHelper.instance.getStaff();
      final match = staff.where((s) => s.name == state.currentStaffName);
      staffId = match.isEmpty ? null : match.first.id;
    }

    // Prevent double-submit
    setState(() => _processingPayment = true);

    try {
      final items = _cart.map(_saleItemFor).toList();

      final saleId = await DatabaseHelper.instance.recordSale(
        staffName: state.currentStaffName ?? 'Unknown',
        items: items,
        paymentMethod: paymentMethod,
        paymentReference: paymentReference,
        amountTendered: amountTendered,
        staffId: staffId,
        etimsPending: etimsEnabled,
      );
      // Every sale is attributed. The ledger records THAT money changed hands;
      // the log records WHO rang it, which is the question a variance review
      // asks and the sales table answers only by a display name.
      await recordActionAudit(
        state,
        action: AuditAction.saleRecorded,
        entity: AuditEntity.sale,
        entityId: 'id-$saleId',
        detail: '${items.length} line(s), $paymentMethod',
      );

      // Before the cart is emptied, while the lines that were sold are still
      // readable, and only once the sale is committed.
      await _deductVariantStockForSale(_cart);

      if (mounted) {
        _announceStatus('Sale recorded: ${formatMoney(_total)}');
        final change = amountTendered - _total;
        setState(() {
          _cart.clear();
          _rebuildReservations();
        });
        _loadProducts(); // Refresh stock
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(!change.isNegative
              ? 'Sale recorded: ${formatMoney(_total)} · Change ${formatMoney(change)}'
              : 'Sale recorded: ${formatMoney(_total)}'),
        ));
      }
      // The sale is committed. Everything below is best-effort and must not be
      // able to fail the checkout it is reporting on — a till that has taken the
      // money has done its job whether or not paper or a KRA receipt follows.
      unawaited(_afterSale(saleId, etimsEnabled: etimsEnabled));
    } catch (e) {
      if (mounted) {
        _announceStatus(
            'Sale could not be completed. Check stock and try again.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Couldn’t complete the sale. Check stock and try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _processingPayment = false);
    }
  }

  /// Prints the receipt and reconciles the tax invoice for a committed sale.
  ///
  /// The single post-sale path. Both checkout routes and the reprint action in
  /// Reports reach the same receipt through the same builder, from the stored
  /// sale, so a reprint cannot drift from the original — and neither can a print
  /// failure touch the sale, which is already committed by the time this runs.
  Future<void> _afterSale(int saleId, {required bool etimsEnabled}) async {
    if (etimsEnabled) {
      // Issue the receipt before printing, so the paper the customer walks away
      // with carries KRA's number. A failure leaves the sale queued and prints
      // without it rather than not printing at all.
      await EtimsService().flushPending(limit: 1);
    }
    final config = await PrinterConfig.load();
    if (!config.printAfterSale) return;
    await _printReceipt(saleId, config);
  }

  /// Prints [saleId]'s receipt, offering a reprint if the printer refuses.
  ///
  /// Returns the result so a caller (print-after-sale, or the reprint action in
  /// Reports) can react. Never throws.
  Future<PrintResult> _printReceipt(int saleId, PrinterConfig config) async {
    final state = context.read<AppState>();
    final result = await ReceiptPrinter().printSale(
      saleId: saleId,
      shopName: state.owner?.shopName ?? 'Duka POS',
      staffRole: state.isOwnerSession ? 'Owner' : state.currentRole,
      config: config,
      vatRatePercent: await DatabaseHelper.instance.getVatRatePercent(),
    );
    if (!mounted) return result;
    if (result.outcome == PrintOutcome.printed ||
        result.outcome == PrintOutcome.disabled) {
      return result;
    }
    _announceStatus('Sale recorded but the receipt did not print.');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context).sellReceiptDidNotPrint),
      // No retry action when the operator has to change something first:
      // offering "Retry" against a refused Bluetooth permission just fails
      // again and teaches the owner that the button does not work.
      action: result.needsUserAction
          ? null
          : SnackBarAction(
              label: AppLocalizations.of(context).actionRetry,
              onPressed: () => unawaited(_printReceipt(saleId, config)),
            ),
    ));
    return result;
  }

  /// Records an M-Pesa sale that could not be pushed, and says so plainly.
  ///
  /// Records `payment_verified = false` rather than pretending the payment
  /// happened. The distinction is what makes the day's figures honest and gives
  /// the owner something specific to reconcile against the payment provider
  /// once there is a signal: "we recorded 14,000 of unverified M-Pesa" is
  /// actionable, whereas a sale quietly booked as confirmed is a number nobody
  /// can trust.
  Future<void> _recordUnverifiedMpesa({required String phoneNumber}) async {
    final state = context.read<AppState>();
    final items = _cart.map(_saleItemFor).toList();

    try {
      final saleId = await DatabaseHelper.instance.recordSale(
        staffName: state.currentStaffName ?? 'Unknown',
        items: items,
        paymentMethod: 'mpesa',
        paymentReference:
            phoneNumber.trim().isEmpty ? null : 'offline-${phoneNumber.trim()}',
        amountTendered: _total,
        paymentVerified: false,
        staffId: state.currentStaffId,
      );
      // An unconfirmed sale is the one most likely to be disputed later, so
      // its attribution matters more, not less.
      await recordActionAudit(
        state,
        action: AuditAction.saleRecorded,
        entity: AuditEntity.sale,
        entityId: 'id-$saleId',
        detail: '${items.length} line(s), M-Pesa, unconfirmed',
      );
      if (!mounted) return;
      _announceStatus('M-Pesa sale recorded. Payment not yet confirmed.');
      setState(_cart.clear);
      _loadProducts();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'No connection, so no M-Pesa prompt was sent. The sale is recorded and '
          'will show as unconfirmed until you reconcile it.',
        ),
      ));
      unawaited(_afterSale(saleId,
          etimsEnabled: await EtimsService().isEnabledForSales()));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              AppLocalizations.of(context).sellSaleNotRecordedNothingCharged),
        ),
      );
    }
  }

  Future<void> _checkoutMpesa() async {
    if (_cart.isEmpty || _processingPayment) return;
    // Read the session before the first await. Everything below is a network
    // round-trip, and `context` must not be touched once the screen could have
    // been popped.
    final state = context.read<AppState>();

    final phoneController = TextEditingController();
    final customerNameController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).sellMpesaPaymentTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context)
                  .sellSaleTotalLabel(formatMoney(_total)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).sellPhoneNumberLabel,
                hintText: AppLocalizations.of(context).sellPhoneNumberHint,
              ),
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: customerNameController,
              decoration: InputDecoration(
                labelText:
                    AppLocalizations.of(context).sellCustomerNameOptionalLabel,
              ),
              autofillHints: const [AutofillHints.name],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context).actionCancel),
          ),
          ElevatedButton(
            onPressed: () {
              final phone = phoneController.text.trim();
              if (phone.length < 10) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                      content: Text(
                          AppLocalizations.of(context).sellEnterValidPhone)),
                );
                return;
              }
              Navigator.pop(ctx, {
                'phone': phone,
                'customer': customerNameController.text.trim(),
              });
            },
            child: Text(AppLocalizations.of(context).sellPayAction),
          ),
        ],
      ),
    );
    phoneController.dispose();
    customerNameController.dispose();

    if (result == null) return;
    if (!mounted) return;

    setState(() => _processingPayment = true);

    try {
      // Offline first, and deliberately before any remote check.
      //
      // A till in a Kenyan shop loses signal constantly, and an M-Pesa sale is
      // a sale regardless: the customer has handed over money in the shop. An
      // STK push needs a network, so with none the only honest outcome is to
      // record the sale and mark the payment unverified — never to refuse it,
      // and never to pretend the push succeeded.
      final linked = await BackendService.isBackendLinked;
      if (!linked) {
        await _recordUnverifiedMpesa(phoneNumber: result['phone'] ?? '');
        return;
      }

      final unsynced = _cart.where((c) => c.product.remoteId == null).toList();
      if (unsynced.isNotEmpty) {
        unawaited(BackendService.syncProductsToBackend());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Some products are not yet synced. The sale will proceed '
                    'and they will be synced in the background.')),
          );
        }
      }

      await BackendService.syncStaffToBackend();
      final staff = await DatabaseHelper.instance.getStaff();
      final matchingStaff =
          staff.where((s) => s.name == state.currentStaffName).toList();
      final cashierProfile = matchingStaff.isEmpty ? null : matchingStaff.first;
      if (!state.isOwnerSession && cashierProfile?.remoteId == null) {
        throw StateError(
            'Cashier profile is not linked yet. Sync staff and try again.');
      }

      // A previous push for this basket may still be awaiting confirmation.
      // Never issue a second STK push for an outstanding reference: that is the
      // double-charge path. Sweep rows the provider will never confirm, then
      // let the operator reconcile anything still outstanding.
      await DatabaseHelper.instance.deleteStalePendingPayments();
      final outstanding =
          await DatabaseHelper.instance.getBlockingPendingPayments();
      if (outstanding.isNotEmpty) {
        if (!mounted) return;
        await _reconcileOutstandingPayment(outstanding.first);
        return;
      }

      final reference = await BackendService.initiatePayment(
        items: _cart
            .map((c) => {
                  'product_id': c.product.remoteId,
                  // The provider bills for a name, and a variant's name is the
                  // one the customer asked for.
                  'product_name': c.foldedName,
                  'qty': c.qty,
                  'portion': c.portion,
                })
            .toList(),
        phoneNumber: result['phone']!,
        staffName: state.currentStaffName ?? 'Unknown',
        staffProfileId: state.isOwnerSession ? null : cashierProfile!.remoteId,
        customerName: result['customer'],
      );

      // Durable record written BEFORE polling. If the poll times out the cart
      // survives, and this row prevents the same basket being pushed again.
      final cartJson = jsonEncode(_cart
          .map((c) => {
                'productId': c.product.id,
                // Already the folded variant name, so a sale booked days later
                // from this snapshot prints and reports the same line the
                // customer was charged for.
                'productName': c.foldedName,
                'variantId': c.variant?.id,
                'qty': c.qty,
                // Minor units, not the Money object. jsonEncode throws on
                // anything it cannot encode, so writing `c.unitPrice` here
                // failed outright — and it failed *after* the payment had been
                // initiated, which is the worst possible moment to lose the
                // record of a sale whose money already moved.
                'unitPrice': c.unitPrice.minorUnits,
                'unitCost': c.unitCost.minorUnits,
                'portion': c.portion,
                'portionMl': c.portionMl,
              })
          .toList());
      await DatabaseHelper.instance.recordPendingPayment(
        reference: reference,
        amount: _total,
        cartJson: cartJson,
        phoneNumber: result['phone'],
        staffName: state.currentStaffName,
        staffId: state.isOwnerSession ? null : cashierProfile?.id,
      );

      // Show waiting dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(context).sellProcessingMpesaTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)
                      .sellCheckPhoneForStk('${result['phone']}'),
                ),
                const SizedBox(height: 8),
                Text(
                    AppLocalizations.of(context).sellReferenceValue(reference)),
              ],
            ),
          ),
        );
      }

      // Poll for status
      final outcome = await BackendService.pollPaymentStatus(reference);

      if (mounted) {
        Navigator.pop(context); // Close waiting dialog

        if (outcome == PaymentOutcome.success) {
          final state = context.read<AppState>();
          // Resolved once, before the sale is written, so the queue decision and the
          // post-sale flush cannot disagree about whether this sale owes KRA a
          // receipt.
          final etimsEnabled = await EtimsService().isEnabledForSales();
          final localItems = _cart.map(_saleItemFor).toList();
          try {
            final saleId = await DatabaseHelper.instance.recordSale(
              staffName: state.currentStaffName ?? 'Unknown',
              items: localItems,
              // The backend already confirmed payment and authoritative stock.
              // Keep the local ledger in sync even if its cached stock drifted.
              enforceStock: false,
              paymentMethod: 'mpesa',
              paymentReference: reference,
              staffId: state.isOwnerSession ? null : cashierProfile?.id,
              etimsPending: etimsEnabled,
            );
            await recordActionAudit(
              state,
              action: AuditAction.saleRecorded,
              entity: AuditEntity.sale,
              entityId: 'id-$saleId',
              detail: '${localItems.length} line(s), M-Pesa, confirmed',
            );
            await _deductVariantStockForSale(_cart);
            await DatabaseHelper.instance.resolvePendingPayment(reference);
            // Same post-sale path as the cash route. Forgetting it here is the
            // easiest mistake in this file to make: the M-Pesa branch has its
            // own confirmation SnackBar and its own error handling, so it reads
            // like a complete flow on its own.
            unawaited(_afterSale(saleId, etimsEnabled: etimsEnabled));
          } catch (_) {
            // Never imply the payment failed: the customer has already paid.
            // Clear the cart to prevent a second charge and surface the
            // ledger repair requirement clearly to the operator.
            _announceStatus(
                'M-Pesa payment succeeded, but the local sale record needs attention.');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Payment succeeded. Local recording failed — contact support before reconciling reports.')),
            );
            setState(() {
              _cart.clear();
              _rebuildReservations();
            });
            _loadProducts();
            return;
          }
          _announceStatus('M-Pesa payment successful. Sale recorded.');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    AppLocalizations.of(context).sellMpesaPaymentSuccessful)),
          );
          setState(() {
            _cart.clear();
            _rebuildReservations();
          });
          _loadProducts();
        } else {
          // Only a definitive decline means the push can safely be retried, so
          // only then does the guard row go. On a timeout the outcome is still
          // unknown: the customer may already have paid, so the row must
          // survive or the same basket can be charged twice.
          if (outcome == PaymentOutcome.failed) {
            await DatabaseHelper.instance.resolvePendingPayment(reference);
          }
          if (!mounted) return;
          _announceStatus(outcome == PaymentOutcome.failed
              ? 'M-Pesa payment failed.'
              : 'M-Pesa payment timed out. Do not charge again.');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(outcome == PaymentOutcome.failed
                    ? 'Payment failed - customer cancelled or insufficient funds'
                    : 'Payment timed out - do not charge again. '
                        'Reference $reference is saved and will be reconciled before another payment.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _announceStatus(
            'M-Pesa payment could not be started. Check your connection and try again.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Payment could not be started. Check your connection and try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _processingPayment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Published for the sign-out sheet, which warns about a part-built cart
    // before ending the session. Safe to assign here: `CartLineCount` is a plain
    // holder with no listeners, so this cannot notify anything mid-build, and
    // reading it in the sheet's own `build` would be equally current.
    context.read<CartLineCount>().set(_cart.length);

    final query = _searchQuery.trim().toLowerCase();
    final filteredProducts = _products
        .where((p) =>
            query.isEmpty ||
            p.name.toLowerCase().contains(query) ||
            p.category.toLowerCase().contains(query))
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        // `autofocus: true` is not a nicety, it is what makes the scanner work.
        //
        // Flutter dispatches a key event ONLY to `primaryFocus` and its
        // ancestors, and drops it entirely when nothing has focus
        // (`focus_manager.dart`: "if (FocusManager.instance.primaryFocus ==
        // null) ... return false"). So a listener that is never focused sees
        // nothing at all in the idle state — which is exactly the state a till
        // is in 99% of the time. This node was created, disposed, and never
        // armed, and the hardware scanner typed into the void.
        //
        // The node remains `skipTraversal`, so it takes focus on mount without
        // joining Tab order. When the cashier taps search, focus moves to the
        // TextField — which is a descendant, so this listener still runs and
        // `_searchHasFocus` disarms it. The two states are both correct.
        return KeyboardListener(
          focusNode: _wedgeFocus,
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: SafeArea(
            child: Flex(
              direction: compact ? Axis.vertical : Axis.horizontal,
              children: [
                // Product catalog
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(context)
                                .sellScanHintSearchProducts,
                            prefixIcon: const Icon(Icons.search),
                            border: const OutlineInputBorder(),
                            suffixIcon: _searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: AppLocalizations.of(context)
                                        .sellClearSearchTooltip,
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  ),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                      // Camera scanning is an explicit action, never an automatic
                      // one: a till with a wedge scanner needs nothing from the
                      // camera, and a phone held over the counter should not open
                      // a camera view on its own.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                button: true,
                                label: AppLocalizations.of(context)
                                    .sellScanCameraLabel,
                                hint: AppLocalizations.of(context)
                                    .sellScanCameraHint,
                                child: OutlinedButton.icon(
                                  onPressed:
                                      _scanInFlight ? null : _scanWithCamera,
                                  icon: const Icon(Icons.qr_code_scanner),
                                  label: Text(AppLocalizations.of(context)
                                      .sellScanBarcode),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : GridView.builder(
                                padding: const EdgeInsets.all(8),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  // From the shared breakpoint vocabulary, so the
                                  // catalogue grid breaks at the SAME widths as
                                  // the shell's navigation affordance. A local
                                  // `maxWidth < 480` is how a phone gets three
                                  // columns while the bottom bar says it is a
                                  // small phone.
                                  crossAxisCount: AdaptiveGrid.columnsFor(
                                    available: constraints.maxWidth,
                                    gap: 8,
                                    minCellWidth: 170,
                                    maxColumns: 3,
                                  ),
                                  // 1.2 rather than 1.0 because the tile reserves
                                  // TWO lines of name, and a square cell clips the
                                  // second one. The aspect ratio is what makes the
                                  // name budget real rather than aspirational.
                                  childAspectRatio: 1.2,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                                itemCount: filteredProducts.length,
                                itemBuilder: (ctx, i) {
                                  final p = filteredProducts[i];
                                  final variants = _variants.of(p);
                                  final sellsAsVariants =
                                      _variants.sellsAsVariants(p);
                                  final fromPrice = sellsAsVariants &&
                                          variants.isNotEmpty
                                      ? _variants.cheapestVariant(p)!.sellPrice
                                      : null;
                                  final matchingCart =
                                      _cart.where((c) => c.product.id == p.id);
                                  final double inCart =
                                      matchingCart.fold<double>(
                                    0,
                                    (double sum, item) => sum + item.stockUnits,
                                  );
                                  final bool canTap =
                                      p.stockQty > 0 || sellsAsVariants;

                                  return _ProductTile(
                                    product: p,
                                    inCart: inCart,
                                    sellsAsVariants: sellsAsVariants,
                                    variantCount: variants.length,
                                    cheapestPrice: fromPrice,
                                    canTap: canTap,
                                    onTap: canTap ? () => _addToCart(p) : null,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),

                // Vertical divider
                compact
                    ? const Divider(height: 1)
                    : const VerticalDivider(width: 1),

                // Cart
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_statusMessage != null)
                              Semantics(
                                liveRegion: true,
                                container: true,
                                label: _statusMessage,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(_statusMessage!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                ),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Semantics(
                                    header: true,
                                    child: Text(
                                        AppLocalizations.of(context)
                                            .sellCartTitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge!)),
                                Text(AppLocalizations.of(context)
                                    .sellCartItemCount(_cart.length)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _cart.isEmpty
                            ? Center(
                                child: Text(AppLocalizations.of(context)
                                    .sellCartEmptyHint))
                            : ListView.builder(
                                itemCount: _cart.length,
                                itemBuilder: (ctx, i) {
                                  final item = _cart[i];
                                  return ListTile(
                                    title: Text(item.cartTitle),
                                    subtitle: Text(item.cartSubtitle),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove),
                                          tooltip: AppLocalizations.of(context)
                                              .sellDecreaseItem(item.label),
                                          onPressed: () => _updateQty(i, -1),
                                        ),
                                        Text(
                                            '${item.qty % 1 == 0 ? item.qty.toInt() : item.qty}'),
                                        IconButton(
                                          icon: const Icon(Icons.add),
                                          tooltip: AppLocalizations.of(context)
                                              .sellIncreaseItem(item.label),
                                          onPressed: () => _updateQty(i, 1),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete),
                                          tooltip: AppLocalizations.of(context)
                                              .sellRemoveItem(item.label),
                                          onPressed: () => _removeFromCart(i),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(AppLocalizations.of(context).sellTotalOnly,
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                Text(
                                  formatMoney(_total),
                                  style:
                                      Theme.of(context).textTheme.headlineSmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        _cart.isEmpty || _processingPayment
                                            ? null
                                            : _checkoutOffline,
                                    icon: const Icon(Icons.payments),
                                    label: Text(AppLocalizations.of(context)
                                        .sellOfflinePaymentAction),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        _cart.isEmpty || _processingPayment
                                            ? null
                                            : _checkoutMpesa,
                                    icon: const Icon(Icons.phone_iphone),
                                    label: Text(AppLocalizations.of(context)
                                        .settingsMpesaMethod),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One line in the cart.
///
/// Carries an optional [variant] directly rather than through a side table keyed
/// by line index. A `Map<int, ProductVariant>` was the other option and it is
/// the worse one: the index is only meaningful while the list is unchanged, so
/// removing a line, reordering, or reading a line after a rebuild would silently
/// attach the wrong variant's price to the wrong bottle. Holding it on the line
/// makes that failure unrepresentable, and this class is declared here rather
/// than in `models.dart`, so it can grow a field without touching a file this
/// feature does not own.
/// Whether a shot can be poured right now, and what to say if it cannot.
///
/// Pure so the wording can be tested. A wrong message here is not cosmetic: the
/// cashier reads it at speed and decides whether to go fix stock, count the
/// drawer, or change the cup, and "not available" sends them to do none of those.
///
/// [available] is the bottle-units left *after* what the cart has already
/// reserved, because a shot in the cart is a shot of the same spirit.
({bool canPour, String reason}) shotAvailability(
  Product product,
  ShotCup cup,
  double available,
) {
  final containerMl = product.bottleMl;
  if (product.unit == ProductUnit.each) {
    // Countable, so there is nothing to measure a pour against. A spirit
    // switched to "each" after its cup was configured reaches here — the cup
    // row still exists, and without this the till would cheerfully offer 25
    // shots of something that has no volume.
    return (
      canPour: false,
      reason: '${product.name} is counted, not measured, so it cannot be poured'
    );
  }
  if (containerMl <= 0) {
    return (
      canPour: false,
      reason: '${product.name} has no volume set, so it cannot be poured'
    );
  }
  final perBottle =
      cup.capacityMl > 0 ? (containerMl / cup.capacityMl).floor() : 0;
  if (perBottle <= 0) {
    return (
      canPour: false,
      reason: 'The cup is bigger than the $containerMl ml bottle'
    );
  }
  final needed = cup.capacityMl / containerMl;
  if (available < needed) {
    return (canPour: false, reason: 'No ${product.name} left to pour');
  }
  return (canPour: true, reason: '$perBottle shots in the bottle');
}

class CartItem {
  final Product product;
  final String portion;

  /// Set when this line is one variant of [product]. A variant is a whole unit
  /// of itself — its own price, its own cost, its own stock — so every derived
  /// figure below switches to it rather than to a fraction of the parent.
  final ProductVariant? variant;

  /// Set when this line is a shot poured from [product].
  ///
  /// A shot is neither of the other two cases. It is not a variant, because it
  /// does not come with its own stock — it is poured out of the parent bottle.
  /// It is not a portion, because "half" and "quarter" cannot describe 30 ml.
  /// It carries a fixed capacity and its own price, so [portion] is
  /// [SalePortion.measured] and the stock it consumes is that capacity as a
  /// fraction of the parent's bottle.
  final ShotCup? shotCup;

  double qty;

  CartItem({
    required this.product,
    required this.portion,
    required this.qty,
    this.variant,
    this.shotCup,
  });

  bool get isVariant => variant != null;
  bool get isShot => shotCup != null;

  /// Bottles this line consumes.
  ///
  /// One for a variant, whatever the parent's bottle size is: a 500ml "Dark" is
  /// half a 750ml bottle to a shopkeeper, but it is one Dark to the ledger, and
  /// treating it as a fraction is how a variant gets charged for a portion it
  /// was never priced in.
  ///
  /// For a shot it is the poured volume as a fraction of the container, so
  /// twenty-five 30 ml shots consume the 750 ml bottle they came from.
  double get fraction {
    if (isVariant) return 1;
    final shot = shotCup;
    if (shot != null) {
      // Capped at one container for the same reason `recordSale` caps it: a
      // capacity larger than the bottle is a configuration mistake, and
      // emptying that bottle is the least wrong reading of it.
      if (shot.capacityMl <= 0 || product.bottleMl <= 0) return 1;
      final f = shot.capacityMl / product.bottleMl;
      return f > 1 ? 1 : f;
    }
    return product.fractionFor(portion);
  }

  double get stockUnits => qty * fraction;

  /// The serving size this line was sold in: the variant's own, the shot cup's
  /// fixed capacity, or the parent's bottle size scaled by the portion.
  int get portionMl {
    final shot = shotCup;
    if (shot != null) return shot.capacityMl;
    return variant?.sizeMl ?? product.mlFor(portion);
  }

  /// "Dark 500 ml" for a variant, the product's name otherwise. What the cart
  /// line, the receipt and the stock-take list all agree on.
  String get label => variant?.label ?? product.name;

  /// The name stored on the sale for this line.
  ///
  /// A variant or a shot is folded into the product's name rather than kept as
  /// a reference to a row that can change: "AAA Vodka" alone does not say
  /// whether the customer was served a 30 ml or a 45 ml shot, and after the cup
  /// is reconfigured the ledger must still say which they got. It is also what
  /// the M-Pesa snapshot stores, so a basket booked days later prints the same
  /// line the customer was charged for.
  String get foldedName {
    final shot = shotCup;
    if (shot != null) return '${product.name} · ${shot.label}';
    final v = variant;
    if (v != null) return foldedVariantName(product, v);
    return product.name;
  }

  /// How the owner reads a size or a quantity: no trailing `.0` on a whole
  /// number, and no "0 ml" on something countable.
  String get sizeLabel {
    final ml = portionMl;
    return ml > 0 ? Volume(ml.toDouble()).display : '';
  }

  /// Money. A portion of a bottle is priced in whole cents and the portion of
  /// the *cost* is scaled the same way, so profit on a half bottle is derived
  /// from real amounts rather than from a float approximation of one. A variant
  /// carries both prices outright, so no scaling happens at all.
  Money get unitPrice {
    final shot = shotCup;
    if (shot != null) return shot.price;
    return variant?.sellPrice ?? product.priceFor(portion);
  }

  Money get unitCost => variant?.costPrice ?? product.costPrice.times(fraction);
  String get portionLabel => portion[0].toUpperCase() + portion.substring(1);

  /// The title of the cart row: a variant names both the product and itself, a
  /// shot names the spirit and the cup, a portion only the product and which
  /// slice of it.
  String get cartTitle {
    if (isVariant) return '${product.name} · ${variant!.label}';
    final shot = shotCup;
    if (shot != null) return '${product.name} · ${shot.label}';
    return '${product.name} · $portionLabel';
  }

  /// The line under it: the size and the line amount, with the size left out
  /// entirely when there is no size to state.
  String get cartSubtitle {
    final amount = formatMoney(total);
    return sizeLabel.isEmpty ? amount : '$sizeLabel · $amount';
  }

  /// The one rounding point per line: [qty] is a quantity and may be fractional,
  /// so the product is quantised here rather than at every intermediate step.
  Money get total => unitPrice.times(qty);
}

/// One product in the till's catalogue grid.
///
/// Extracted as a class rather than left inline because it is the most-tapped
/// control in the app, and a 70-line inline block in an `itemBuilder` is
/// untestable in isolation.
class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.inCart,
    required this.sellsAsVariants,
    required this.variantCount,
    required this.cheapestPrice,
    required this.canTap,
    required this.onTap,
  });

  final Product product;

  /// Units already in the cart, as a fraction — a shot can be poured in 0.25
  /// steps, so this is not an integer count.
  final double inCart;

  final bool sellsAsVariants;
  final int variantCount;
  final Money? cheapestPrice;
  final bool canTap;
  final VoidCallback? onTap;

  /// Lines of name the tile reserves.
  ///
  /// Two, and the tile is sized so two lines FIT rather than so two lines are
  /// permitted. That distinction is the whole difference between a name that is
  /// readable and a name that is silently cut: the cell grows taller instead of
  /// the text shrinking or clipping.
  static const int _nameLines = 2;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    final String priceLine = sellsAsVariants
        ? (cheapestPrice == null
            ? 'No variants yet'
            : 'From ${formatMoney(cheapestPrice!)}')
        : formatMoney(product.sellPrice);

    // The stock line carries a WORD as well as a tone. It used to carry only a
    // red colour, which is invisible to a deuteranopic cashier, to a greyscale
    // screenshot, and to a screen reader.
    final String stockLine = '${product.stockQty.round()} in stock';

    return Semantics(
      button: canTap,
      // One node carrying the whole tile: a cashier stepping through the grid with
      // TalkBack should hear "Kenyatta bread, KSh 60, 12 in stock, add to cart",
      // not four separate stops for name, price, count and action.
      label: sellsAsVariants
          ? '${product.name}, from '
              '${cheapestPrice == null ? 'no variants' : formatMoney(cheapestPrice!)}, '
              '$variantCount variants, $stockLine'
          : '${product.name}, ${formatMoney(product.sellPrice)}, $stockLine',
      hint: !canTap
          ? AppLocalizations.of(context).sellOutOfStock
          : sellsAsVariants
              ? 'Double tap to choose a variant'
              : 'Double tap to add to the cart',
      excludeSemantics: true,
      child: ExcludeSemantics(
        child: SurfaceCard(
          onTap: onTap,
          child: Stack(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.all(spacing.sm),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        product.name,
                        textAlign: TextAlign.center,
                        maxLines: _nameLines,
                        // Ellipsis, not `visible`.
                        //
                        // `visible` was defended in a comment as "no ellipsis
                        // here, the product would be spelled with a trailing
                        // dot", and it pointed at the overflow matrix as the
                        // guard. But that matrix only exercises
                        // ui/components/ and page.dart — nothing in this file.
                        // So a 120-character name (the editor's own limit,
                        // models.dart) rendered as `maxLines` lines with NO
                        // ellipsis at all: `TextPainter` silently drops lines
                        // past `maxLines`, and a cashier saw a name cut
                        // mid-word with nothing saying text was lost.
                        //
                        // An ellipsis IS the signal. It is read by screen
                        // readers as "text truncated", which is exactly the
                        // truth, and the tile's `Semantics` label above carries
                        // the full name for whoever needs it spoken.
                        overflow: TextOverflow.ellipsis,
                        style: type.titleSmall,
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      priceLine,
                      textAlign: TextAlign.center,
                      // Tabular figures: a column of prices that shifts sideways
                      // as the digit count changes cannot be scanned.
                      style: AppTypography.money(
                        context,
                        size: 14,
                        weight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          product.isLow
                              ? StatusTone.warning.icon
                              : StatusTone.success.icon,
                          size: 12,
                          color:
                              product.isLow ? colors.warning : colors.success,
                        ),
                        SizedBox(width: spacing.xs),
                        Text(
                          stockLine,
                          style: type.labelSmall?.copyWith(
                            color: product.isLow
                                ? colors.warning
                                : colors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (inCart > 0)
                PositionedDirectional(
                  top: spacing.xs,
                  end: spacing.xs,
                  child: _CartCountPip(count: inCart),
                ),
              if (!canTap)
                Positioned.fill(
                  child: DecoratedBox(
                    // A scrim rather than a disabled colour on the text: the
                    // contents stay legible so the cashier can still read WHAT is
                    // out of stock, which is the information they need.
                    decoration: BoxDecoration(
                      color: colors.canvas.withValues(alpha: 0.72),
                      borderRadius: AppShapes.of(context).controlRadius,
                    ),
                    child: Center(
                      child: StatusChip(
                        tone: StatusTone.danger,
                        text: AppLocalizations.of(context).sellOutOfStock,
                        dense: true,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How many units of this product are already in the cart.
class _CartCountPip extends StatelessWidget {
  const _CartCountPip({required this.count});

  /// Fractional, because a shot can be poured in quarter steps: the pip shows
  /// `3` while it is `3.0`, and `1.5` while it is not.
  final double count;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final String label = count == count.roundToDouble()
        ? '${count.toInt()}'
        : count.toStringAsFixed(1);

    return Semantics(
      label: '$label in the cart',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: colors.accent,
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: AppTypography.of(context).labelSmall?.copyWith(
                color: colors.onAccent,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
        ),
      ),
    );
  }
}
