import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../routing/routes.dart';
import '../models/audit_log.dart';
import '../services/app_state.dart';
import '../services/audit_actor.dart';
import '../services/backend_service.dart';
import '../services/session_refresh_mixin.dart';
import '../services/barcode/barcode_service.dart';
import '../services/barcode/scan_input_service.dart';
import '../services/etims/etims_service.dart';
import '../services/printer/printer_config.dart';
import '../services/printer/receipt_printer.dart';
import '../widgets/sign_out_sheet.dart';
import '../widgets/product_tile.dart';
import '../widgets/sell_page.dart';
import '../widgets/serving_choice_sheet.dart';
import '../routing/home_shell.dart';
import '../widgets/variant_catalogue.dart';
import '../l10n/generated/app_localizations.dart';
import '../ui/components/controls.dart';
import '../ui/components/success_view.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/layout/page.dart';
import '../models/models.dart';
import '../db/database_helper.dart';
import '../utils/money.dart';
import '../utils/units.dart';

class SellScreen extends StatefulWidget {
  const SellScreen({super.key});

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen>
    with SessionRefresh<SellScreen> {
  static const _pollTimeout = Duration(seconds: 20);
  final List<CartItem> _cart = [];
  final Map<int, double> _reservedByProduct = <int, double>{};
  final Map<int, double> _reservedByVariant = <int, double>{};

  late final HomeShellTabs _shellTabs;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _wedge = WedgeScannerBuffer();

  final _wedgeFocus = FocusNode(skipTraversal: true);
  List<Product> _products = [];

  VariantCatalogue _variants = VariantCatalogue.empty;

  List<ShotCup> _shots = const [];

  String _searchQuery = '';
  bool _loading = true;
  bool _processingPayment = false;
  EtimsIssuedReceipt? _pendingEtimsReceipt;
  bool _portionSheetOpen = false;
  bool _scanInFlight = false;
  String? _statusMessage;

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
    final generation = _shellTabs.catalogueGenerationSeen;
    if (generation == _seenCatalogueGeneration) return;
    _seenCatalogueGeneration = generation;
    _loadProducts();
  }

  @override
  void clearForSession() {
    _cart.clear();
    _reservedByProduct.clear();
    _reservedByVariant.clear();
    _statusMessage = null;
    _searchController.clear();
  }

  @override
  Future<void> reloadFromSession() => _loadProducts();

  @override
  void dispose() {
    _shellTabs.removeListener(_onShellChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _wedgeFocus.dispose();
    super.dispose();
  }

  /// Why the catalogue could not be read, or null.
  ///
  /// A till cannot sell without a catalogue, so this takes the pane over
  /// rather than being a toast: the error says what happened, and the retry
  /// button is the one thing that can fix it.
  String? _catalogueError;

  Future<void> _loadProducts() async {
    final db = DatabaseHelper.instance;
    final List<Object> results;
    try {
      results = await Future.wait<Object>([
        db.getProducts(),
        VariantCatalogue.load(),
        db.getShotCups(),
      ]);
    } on Object {
      // The read failed. Without this the loader's future ended in an
      // unhandled error and `_loading` stayed true FOREVER, so the pane
      // showed a spinner that never stopped — a till telling the cashier to
      // wait for something that was never going to arrive.
      if (!mounted) return;
      setState(() {
        _catalogueError =
            AppLocalizations.of(context).sellCatalogueLoadFailedMessage;
        _loading = false;
      });
      return;
    }
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
        // The catalogue is readable again, so the error has gone.
        _catalogueError = null;
      });
    }
  }

  List<ShotCup> _shotsFor(Product product) =>
      _shots.where((c) => c.productId == product.id).toList();

  double _cartUnitsFor(Product product) =>
      _reservedByProduct[product.id] ?? 0.0;

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
      // The variant each line was sold as, so the sale's own transaction moves
      // that variant's count. It used to be a second, later deduction — a
      // window in which a crash sold a bottle and kept the count.
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
          variantId: (line['variantId'] as num?)?.toInt(),
          variantName: line['variantName'] as String? ?? '',
        ));
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

  /// The codes waiting to be added to the cart.
  ///
  /// A camera that keeps reading produces codes faster than a database lookup
  /// can answer, so they queue here rather than being dropped: the second
  /// scan of a trolley must not be the one that is lost.
  final List<ScanResult> _scanQueue = <ScanResult>[];

  /// Handles a code that arrived from a wedge scanner or the camera.
  ///
  /// Both sources funnel through here so a product added by scan is
  /// indistinguishable from one added by tapping the tile — same portion
  /// default, same stock re-validation, same merge into an existing line.
  ///
  /// The codes are applied ONE AT A TIME, in the order they were read. A
  /// camera reading continuously hands over the next code while the previous
  /// one is still being looked up, and that code waits its turn instead of
  /// being dropped on the floor.
  Future<void> _handleScan(ScanResult scan) async {
    _scanQueue.add(scan);
    if (_scanInFlight) return;
    _scanInFlight = true;
    try {
      while (_scanQueue.isNotEmpty) {
        await _applyScan(_scanQueue.removeAt(0));
      }
    } finally {
      _scanInFlight = false;
    }
  }

  /// Adds ONE scanned code to the cart.
  ///
  /// Resolved through `getScanTarget` rather than by barcode alone, because a
  /// code can belong to the product *or* to one of its variants and the two sell
  /// differently: a variant's code must add that variant, at the variant's price,
  /// out of the variant's stock. Resolving to the product and stopping there is
  /// charging the wrong price for the wrong thing.
  Future<void> _applyScan(ScanResult scan) async {
    final target = await DatabaseHelper.instance.getScanTarget(scan.normalised);
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
      final message =
          AppLocalizations.of(context).sellScanVariantOnlyMessage(product.name);
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
    //
    // The scanner keeps reading until the operator closes it, so the codes
    // arrive WHILE it is open. The session is the channel between the two:
    // the scanner writes each code into it as it is read, and the till adds
    // each code to the cart as it lands. A scanner that stopped to hand back
    // one code and waited to be asked again would make a trolley take a
    // hundred taps.
    final ScanSession session = ScanSession();
    final StreamSubscription<ScanResult> subscription =
        session.codes.listen((ScanResult scan) {
      unawaited(_handleScan(scan));
    });

    try {
      final GoRouter router = GoRouter.of(context);
      // The popped copy is ignored ON PURPOSE: it is the list the scanner
      // hands back on its way out, for a route opened without a till behind
      // it. This till has already had every code live, and adding them again
      // would sell the same item twice.
      await router.push<List<ScanResult>>(Routes.cameraScan, extra: session);
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
    } finally {
      await subscription.cancel();
      await session.dispose();
    }
  }

  /// What the till grid needs to draw one product.
  ///
  /// Assembled here rather than inside the grid, because the rules — what
  /// counts as in the cart, whether the tile can be tapped, which price is the
  /// cheapest variant's — belong to the screen that owns the cart and the
  /// catalogue, not to a widget that draws a list.
  ProductTileData _tileDataFor(Product product) {
    final List<ProductVariant> variants = _variants.of(product);
    final bool sellsAsVariants = _variants.sellsAsVariants(product);
    final Money? fromPrice = sellsAsVariants && variants.isNotEmpty
        ? _variants.cheapestVariant(product)!.sellPrice
        : null;

    final double inCart = _cart
        .where((CartItem item) => item.product.id == product.id)
        .fold<double>(
          0,
          (double sum, CartItem item) => sum + item.stockUnits,
        );

    return ProductTileData(
      product: product,
      inCart: inCart,
      sellsAsVariants: sellsAsVariants,
      variantCount: variants.length,
      cheapestPrice: fromPrice,
      canTap: product.stockQty > 0 || sellsAsVariants,
    );
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
    final l10n = AppLocalizations.of(context);
    // Nothing to choose means nothing to sell: a product with no price of its
    // own, no half, no quarter, no cup and no variant has never been set up
    // for the till. Opening an empty sheet would look like a broken tap, so
    // the till says which step is missing.
    final bool hasSomethingToSell = sellsAsVariants ||
        shots.isNotEmpty ||
        product.sellsWhole ||
        product.halfPrice != null ||
        product.quarterPrice != null;
    if (!hasSomethingToSell) {
      _portionSheetOpen = false;
      _say(l10n.sellNoPriceSetYet);
      return;
    }
    ServingChoice? choice;
    try {
      choice = await showModalBottomSheet<ServingChoice>(
        context: context,
        // The sheet scrolls now. It used to be a column in a sheet limited to
        // half the screen, and the quarter — the last portion before the
        // shots — was the first thing to go when the sheet was too short. On a
        // phone held sideways it always went.
        isScrollControlled: true,
        builder: (sheetContext) => ServingChoiceSheet(
          product: product,
          variants: variants,
          sellsAsVariants: sellsAsVariants,
          shots: shots,
          remainingStock: product.stockQty - _cartUnitsFor(product),
        ),
      );
    } finally {
      _portionSheetOpen = false;
    }
    if (choice == null || !mounted) return;
    // The sheet had the focus, and the focus goes back to the till — NOT to
    // the search field, which is a text field and would open the keyboard over
    // the catalogue with the cashier's half-typed name in it.
    _returnFocusToTill();
    if (choice is ServingChoiceShot) {
      final ShotCup cup = choice.cup;
      await _addToCartDirect(product, SalePortion.measured, shotCup: cup);
      return;
    }
    if (choice is ServingChoiceVariant) {
      final ProductVariant variant = choice.variant;
      await _addToCartDirect(product, 'full', variant: variant);
      return;
    }
    await _addToCartDirect(
      product,
      switch (choice) {
        ServingChoiceHalf() => 'half',
        ServingChoiceQuarter() => 'quarter',
        _ => 'full',
      },
    );
  }

  /// Gives the focus back to the till's own input.
  ///
  /// The scanner's listener is the till's focus when nothing else is: it is
  /// the thing that hears a barcode. A modal sheet takes the focus while it
  /// is open, and on the way out the framework gives it to the next focusable
  /// it can find — which is the SEARCH FIELD, because a text field wants the
  /// keyboard and the keyboard covers the catalogue.
  ///
  /// So the till says where the focus goes.
  void _returnFocusToTill() {
    if (_searchFocus.hasFocus) {
      _searchFocus.unfocus();
    }
    if (_wedgeFocus.canRequestFocus) {
      _wedgeFocus.requestFocus();
    }
  }

  void _say(String message) {
    _announceStatus(message);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

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
            ? AppLocalizations.of(context).sellAllVariantInCart(variant.name)
            : AppLocalizations.of(context).sellNoVariantLeft(variant.name));
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
      // A cup with NO size takes nothing that can be measured, so nothing is
      // reserved against the bottle: the owner did not say how big the shot
      // is, and the app does not guess. The shot is still sold, at its price.
      final needed = shotCup.capacityMl <= 0 || current.bottleMl <= 0
          ? 0.0
          : (shotCup.capacityMl / current.bottleMl).clamp(0.0, 1.0);
      final available = current.stockQty - _cartUnitsFor(current);
      if (available < needed) {
        _say(AppLocalizations.of(context)
            .sellNotEnoughForShot(current.name));
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
      _say(AppLocalizations.of(context).sellNotEnoughLeft(current.name));
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

  Money get _total => sumMoney(_cart.map((item) => item.total));

  static const _offlinePaymentLabels = <String, String>{
    'cash': 'Cash',
    'card': 'Card',
    'bank_transfer': 'Bank transfer',
    'mobile_money_manual': 'Mobile money (manual)',
  };

  /// The name of a payment method, in the app's own words.
  ///
  /// The same names the receipt prints, so the screen and the paper cannot
  /// disagree about how a sale was paid for.
  String _paymentLabel(String method) {
    switch (method) {
      case 'cash':
        return AppLocalizations.of(context).sellCompletePaidCash;
      case 'mpesa':
        return AppLocalizations.of(context).sellCompletePaidMpesa;
      case 'card':
        return AppLocalizations.of(context).sellCompletePaidCard;
      case 'bank_transfer':
        return AppLocalizations.of(context).sellCompletePaidBank;
      case 'mobile_money_manual':
        return AppLocalizations.of(context).sellCompletePaidMobileMoney;
      default:
        return AppLocalizations.of(context).sellCompletePaidOtherGeneric;
    }
  }

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
        // Which variant was sold, so the sale transaction can move that
        // variant's OWN count. The deduction happens inside the sale's
        // transaction, not after it — see [DatabaseHelper.recordSale].
        variantId: line.variant?.id,
        variantName: line.variant?.name ?? '',
      );

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

      // The variant counts moved with the sale itself, inside its transaction.
      // Nothing is deducted here: a second, later deduction was the window in
      // which a crash sold a bottle and kept the count.

      if (mounted) {
        // The sale's total, captured BEFORE the cart is cleared.
        //
        // `_total` is a getter over the cart, so reading it after the clear
        // answers "KSh 0" — and the success sheet and the popup both did
        // exactly that: the change line was right (captured first) while the
        // amount above it read zero. The number the cashier is shown is the
        // number the customer just paid, so it is taken once, here, and
        // carried to every surface that reports this sale.
        final Money saleTotal = _total;
        _announceStatus('Sale recorded: ${formatMoney(saleTotal)}');
        final Money change = amountTendered - saleTotal;
        setState(() {
          _cart.clear();
          _rebuildReservations();
        });
        _loadProducts(); // Refresh stock
        if (!mounted) return;
        // CASH gets the full screen. Everything else gets a popup.
        //
        // The reason is the CHANGE. A cash sale has change to hand over, and
        // a person counting money out of a drawer needs the amount and the
        // change on screen while they count. A card, a bank transfer and a
        // manual mobile-money entry have no change — the money left in one
        // piece — so there is nothing to hold the cashier on a screen, and
        // a screen there is a screen between the cashier and the next
        // customer.
        if (paymentMethod == 'cash') {
          await _showSaleComplete(
            method: AppLocalizations.of(context).sellCompletePaidCash,
            total: saleTotal,
            paid: amountTendered,
            change: change,
          );
        } else {
          // The method is NAMED, not assumed. This used to say "Paid in cash"
          // for a card payment, and "Change due KSh 0.00" under it — two
          // statements that were both false on a sale where no cash changed
          // hands.
          //
          // gen-l10n sorts the placeholders ALPHABETICALLY, so the generated
          // signature is (amount, method) even though the sentence reads
          // "{method} · {amount}". Passing the label first printed the amount
          // where the method belongs.
          showAppSnackBar(
            context,
            message: AppLocalizations.of(context).sellCompletePaidOther(
              formatMoney(saleTotal),
              _paymentLabel(paymentMethod),
            ),
          );
        }
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

  /// The moment the sale is done: the amount, the change, and one button.
  ///
  /// A SHEET rather than a route: it is the end of a transaction, not a
  /// place. The cashier taps "Next sale" and is back on the till with an
  /// empty cart in one tap — a route would put a back button between the
  /// cashier and the next customer.
  ///
  /// Dismissable by tapping outside it and by dragging it down, so a sheet
  /// that somehow cannot be dismissed can never hold the till hostage.
  Future<void> _showSaleComplete({
    required String method,
    required Money total,
    required Money paid,
    required Money change,
  }) async {
    final l10n = AppLocalizations.of(context);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // The sheet covers most of the screen: the amount is the answer to the
      // question the cashier came here for, and it is read at arm's length
      // while they count the change out.
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (BuildContext sheetContext) => SafeArea(
        child: SuccessView(
          title: l10n.sellCompleteTitle,
          // The method: the one fact that changes what the cashier says out
          // loud, and the one the reports ask for.
          message: method,
          amountLabel: formatMoney(total),
          // Paid, and what to hand back. Both are said even when the change
          // is nothing — "Change 0" is the answer to "do I owe them?" and
          // silence on that line makes a cashier count the notes again.
          facts: <SuccessFact>[
            SuccessFact(
              label: l10n.sellCompleteFactPaid,
              value: formatMoney(paid),
            ),
            SuccessFact(
              label: l10n.sellCompleteFactChange,
              value: formatMoney(change.isNegative ? Money.zero : change),
            ),
          ],
          onNext: () => Navigator.pop(sheetContext),
          nextLabel: l10n.sellCompleteNext,
        ),
      ),
    );
  }

  /// Prints the receipt and reconciles the tax invoice for a committed sale.
  ///
  /// The single post-sale path. Both checkout routes and the reprint action in
  /// Reports reach the same receipt through the same builder, from the stored
  /// sale, so a reprint cannot drift from the original — and neither can a print
  /// failure touch the sale, which is already committed by the time this runs.
  Future<void> _afterSale(int saleId, {required bool etimsEnabled}) async {
    if (etimsEnabled) {
      // Issue this sale's receipt before printing, so the customer's paper
      // carries KRA's number. A failure leaves the sale queued and prints an
      // "eTIMS pending" line rather than holding the customer at the counter.
      final issued = await EtimsService().flushFor(saleId);
      if (!mounted) return;
      _pendingEtimsReceipt = issued;
    }
    final config = await PrinterConfig.load();
    if (!config.printAfterSale) {
      _pendingEtimsReceipt = null;
      return;
    }
    await _printReceipt(saleId, config,
        etimsPending: etimsEnabled && _pendingEtimsReceipt == null);
    if (!mounted) return;
    _pendingEtimsReceipt = null;
  }

  Future<PrintResult> _printReceipt(int saleId, PrinterConfig config,
      {bool etimsPending = false}) async {
    final state = context.read<AppState>();
    final saleRow = await DatabaseHelper.instance.getSaleRowById(saleId);
    final vatRate = saleRow == null
        ? await DatabaseHelper.instance.getVatRatePercent()
        : await DatabaseHelper.instance.vatRateForSale(saleRow);
    final prefs = await SharedPreferences.getInstance();
    final pricesIncludeVat = prefs.getBool('prices_include_vat') ?? true;
    final result = await ReceiptPrinter().printSale(
      saleId: saleId,
      shopName: state.owner?.shopName ?? 'Duka POS',
      staffRole: state.isOwnerSession ? 'Owner' : state.currentRole,
      config: config,
      vatRatePercent: vatRate,
      pricesIncludeVat: pricesIncludeVat,
      etimsReceiptNumber: _pendingEtimsReceipt?.receiptNumber,
      etimsVerificationPayload: _pendingEtimsReceipt?.verificationUrl,
      etimsPending: etimsPending,
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
                'variantName': c.variant?.name ?? '',
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

      // Show waiting dialog.
      //
      // `showDialog` pushes onto the ROOT navigator, so popping it with the
      // screen's own context closed the SELL SCREEN and left the spinner
      // hanging over the next route. The dialog also refuses the back button,
      // so the only way out of it is the one that pops it — which makes the
      // root navigator's top route unambiguously this dialog.
      if (mounted) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => PopScope(
            canPop: false,
            child: AlertDialog(
              title:
                  Text(AppLocalizations.of(context).sellProcessingMpesaTitle),
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
                  Text(AppLocalizations.of(context)
                      .sellReferenceValue(reference)),
                ],
              ),
            ),
          ),
        );
      }

      // Poll for status
      final outcome = await BackendService.pollPaymentStatus(reference);

      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .pop(); // Close waiting dialog

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
          // Same rule as the cash route: the total is read BEFORE the cart
          // goes, or the popup reports a sale of nothing.
          final Money mpesaTotal = _total;
          setState(() {
            _cart.clear();
            _rebuildReservations();
          });
          _loadProducts();
          if (!mounted) return;
          // A POPUP, not the sale-complete screen.
          //
          // The screen is for a cash sale, where there is change to count
          // out. An M-Pesa payment has no change and no cash to hand over —
          // the customer has already paid — so there is nothing to hold the
          // cashier on a screen while the next customer waits.
          //
          // (amount, method) — gen-l10n sorts the placeholders alphabetically.
          showAppSnackBar(
            context,
            message: AppLocalizations.of(context).sellCompletePaidOther(
              formatMoney(mpesaTotal),
              AppLocalizations.of(context).sellCompletePaidMpesa,
            ),
          );
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

    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    final query = _searchQuery.trim().toLowerCase();
    final filteredProducts = _products
        .where((p) =>
            query.isEmpty ||
            p.name.toLowerCase().contains(query) ||
            p.category.toLowerCase().contains(query))
        .toList();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // The screen's own name, on the canvas.
                //
                // It used to be a brand strip — a logo and the wordmark, and
                // no name for the screen. The shell's bar carries the mark
                // now, and the till needs its rows: this line is the one
                // thing above the catalogue that says what the screen is.
                Padding(
                  // The page's gutter, from the shared helper, so the till's
                  // chrome lines up with the dashboard's.
                  padding: EdgeInsetsDirectional.only(
                    start: PageGutter.of(context).left,
                    end: PageGutter.of(context).right,
                    top: spacing.sm,
                    bottom: spacing.sm,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.navSell,
                      style: AppTypography.of(context).titleLarge,
                    ),
                  ),
                ),
                // The two panes.
                //
                // Inside an `Expanded`, and that word is the whole fix: a
                // Column hands its non-flexible children an UNBOUNDED height,
                // and the pane layout divides a height. Given an unbounded one
                // it divided infinity, the grid's scroll extent became
                // infinite, and the sliver's index arithmetic threw "Infinity
                // or NaN to Int" the moment the till opened on a phone.
                Expanded(
                  child: SellPaneLayout(
                    compact: compact,
                    catalogue: SellCataloguePane(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      query: _searchQuery,
                      onQueryChanged: (String value) =>
                          setState(() => _searchQuery = value),
                      onClearQuery: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      onScan: _scanWithCamera,
                      scanning: _scanInFlight,
                      loading: _loading,
                      items: <ProductTileData>[
                        for (final Product p in filteredProducts)
                          _tileDataFor(p),
                      ],
                      onProduct: _addToCart,
                      error: _catalogueError,
                      onRetry: _loadProducts,
                    ),
                    cart: SellCartPane(
                      lines: _cartLines(l10n),
                      itemCountLabel: l10n.sellCartItemCount(_cart.length),
                      totalLabel: formatMoney(_total),
                      emptyHint: l10n.sellCartEmptyHint,
                      offlineLabel: l10n.sellOfflinePaymentAction,
                      mpesaLabel: l10n.settingsMpesaMethod,
                      onOffline: _checkoutOffline,
                      onMpesa: _checkoutMpesa,
                      processing: _processingPayment,
                      statusMessage: _statusMessage,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The cart, as the pane draws it.
  ///
  /// Built here rather than passed in, because the pane is a view and the
  /// cart is the screen's business.
  List<SellCartLine> _cartLines(AppLocalizations l10n) {
    return <SellCartLine>[
      for (int i = 0; i < _cart.length; i++)
        SellCartLine(
          title: _cart[i].cartTitle,
          subtitle: _cart[i].cartSubtitle,
          quantity: _quantityText(_cart[i].qty),
          decreaseLabel: l10n.sellDecreaseItem(_cart[i].label),
          increaseLabel: l10n.sellIncreaseItem(_cart[i].label),
          removeLabel: l10n.sellRemoveItem(_cart[i].label),
          onDecrease: () => _updateQty(i, -1),
          onIncrease: () => _updateQty(i, 1),
          onRemove: () => _removeFromCart(i),
        ),
    ];
  }

  /// A quantity, as the cashier reads it.
  ///
  /// 2, or 0.5 — never 0.5 written as "1" and never 0.4 written as "0".
  static String _quantityText(double qty) =>
      qty % 1 == 0 ? '${qty.toInt()}' : qty.toStringAsFixed(1);
}

/// One line in the cart.
///
/// Carries an optional [variant] directly rather than through a side table keyed
/// by line index. A `Map<int, ProductVariant>` was the other option and it is
/// the worse one: the index is only meaningful while the list is unchanged, so
/// removing a line, reordering, or reading a line after a rebuild would silently
/// attach the wrong variant's price to the wrong bottle. Holding it on the line

class CartItem {
  final Product product;
  final String portion;

  final ProductVariant? variant;

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

  double get fraction {
    if (isVariant) return 1;
    final shot = shotCup;
    if (shot != null) {
      // Capped at one container for the same reason `recordSale` caps it: a
      // capacity larger than the bottle is a configuration mistake, and
      // emptying that bottle is the least wrong reading of it.
      // A shot with no size takes nothing that can be measured, so it costs
      // the drink nothing and reserves nothing: the whole price is the
      // profit, because the drink that went into it is not being counted.
      if (shot.capacityMl <= 0 || product.bottleMl <= 0) return 0;
      final f = shot.capacityMl / product.bottleMl;
      return f > 1 ? 1 : f;
    }
    return product.fractionFor(portion);
  }

  double get stockUnits => qty * fraction;

  int get portionMl {
    final shot = shotCup;
    if (shot != null) return shot.capacityMl;
    return variant?.sizeMl ?? product.mlFor(portion);
  }

  String get label => variant?.label ?? product.name;

  String get foldedName {
    final shot = shotCup;
    if (shot != null) return '${product.name} · ${shot.label}';
    final v = variant;
    if (v != null) return foldedVariantName(product, v);
    return product.name;
  }

  String get sizeLabel {
    final ml = portionMl;
    return ml > 0 ? Volume(ml.toDouble()).display : '';
  }

  Money get unitPrice {
    final shot = shotCup;
    if (shot != null) return shot.price;
    return variant?.sellPrice ?? product.priceFor(portion);
  }

  Money get unitCost => variant?.costPrice ?? product.costPrice.times(fraction);
  String get portionLabel => portion[0].toUpperCase() + portion.substring(1);

  String get cartTitle {
    if (isVariant) return '${product.name} · ${variant!.label}';
    final shot = shotCup;
    if (shot != null) return '${product.name} · ${shot.label}';
    return '${product.name} · $portionLabel';
  }

  String get cartSubtitle {
    final amount = formatMoney(total);
    return sizeLabel.isEmpty ? amount : '$sizeLabel · $amount';
  }

  Money get total => unitPrice.times(qty);
}
