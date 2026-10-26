// The till page's LAYOUT: the catalogue, the cart, and how they sit together.
//
// WHY THIS IS ITS OWN FILE
//
// The layout used to be a nest of Columns and Flexes written inline in the
// screen's build method, and it had a bug only a phone could find.
//
// A Column hands its NON-FLEXIBLE children an unbounded height — that is how
// a Column shrink-wraps them. The page's pane Flex holds two Expanded
// children, and it was one of those non-flexible children, so it was given an
// unbounded height. In debug that is an assertion ("RenderFlex children have
// non-zero flex but incoming height constraints are unbounded"). In a RELEASE
// build the assertion is gone and the unbounded height flows into the
// catalogue's grid: the grid's scroll extent becomes infinite, and the
// sliver's index arithmetic throws "Unsupported operation: Infinity or NaN to
// Int" the moment the till opens.
//
// The fix is not a patch. The page's arrangement is ONE decision, made in ONE
// place, with a height that is bounded by construction — and the decision can
// be tested without a database, a session, or a till in front of you.
//
// WHAT THE LAYOUT IS FOR
//
// A till is looked at, not read. The catalogue wants the screen; the cart
// wants to be visible and reachable. On a wide screen — a tablet on the
// counter, a landscape till — they sit side by side, because the cashier
// looks at one and touches the other. On a phone they stack, the catalogue
// above, because a thumb reaches the bottom of the screen and the bottom of
// the screen is where the cart's money is.

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/states.dart';
import '../ui/layout/page.dart';
import 'product_tile.dart';

/// The till's page: the catalogue and the cart, arranged.
///
/// One widget, one decision. It REQUIRES a bounded box: the panes divide a
/// height, and a height that is not there is the bug this file exists to
/// prevent. A debug assertion says so plainly rather than letting the failure
/// arrive three frames later as an arithmetic error about infinity.
class SellPaneLayout extends StatelessWidget {
  const SellPaneLayout({
    required this.catalogue,
    required this.cart,
    required this.compact,
    super.key,
  });

  /// The catalogue: the search row and the grid of products.
  final Widget catalogue;

  /// The cart: what is in it, and what it costs.
  final Widget cart;

  /// Whether the page is one column (a phone) rather than two (a tablet).
  final bool compact;

  /// Whether a box can hold a layout that DIVIDES a height.
  ///
  /// A pane layout splits the space between two panes, so it needs a height
  /// to split. A box with no height means the thing above it is
  /// shrink-wrapping it — and a grid in an unbounded box has an infinite
  /// scroll extent, which is the crash this layout exists to prevent.
  static bool canDivide(BoxConstraints constraints) =>
      constraints.hasBoundedHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        assert(
          canDivide(constraints),
          'The till page needs a bounded height. It is being given '
          '${constraints.maxHeight}, which means the box above it is '
          'shrink-wrapping it — and a grid in an unbounded box has an '
          'infinite scroll extent, which is the crash this layout exists to '
          'prevent.',
        );

        if (compact) {
          // The cart's share of the page grows with the text.
          //
          // The cart holds the one part of the till that CANNOT scroll away:
          // the total, and the button that takes the money. Its pinned block
          // is measured in lines of text, so at 200% text it is twice as tall
          // — while the catalogue above it is a grid that can scroll forever.
          //
          // Splitting the page evenly is what overflowed: the cart's pinned
          // block outgrew its share, and the overflow came out of the money
          // and the payment button — the two things a cashier is looking at
          // the moment they matter.
          final double scale = MediaQuery.textScalerOf(context).scale(1);
          final int catalogueFlex = scale > 1.5 ? 2 : (scale > 1 ? 2 : 3);
          final int cartFlex = scale > 1.5 ? 6 : (scale > 1 ? 3 : 2);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(flex: catalogueFlex, child: catalogue),
              const Divider(height: 1),
              Expanded(flex: cartFlex, child: cart),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(flex: 3, child: catalogue),
            const VerticalDivider(width: 1),
            Expanded(flex: 2, child: cart),
          ],
        );
      },
    );
  }
}

/// The catalogue: the search row, and the grid of products under it.
class SellCataloguePane extends StatelessWidget {
  const SellCataloguePane({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onScan,
    required this.scanning,
    required this.loading,
    required this.items,
    required this.onProduct,
    this.error,
    this.onRetry,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// What the cashier has typed.
  final String query;

  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;

  /// Opens the camera scanner.
  final VoidCallback onScan;

  /// Whether a scan is already running, so the button is not a second press.
  final bool scanning;

  /// Whether the catalogue is still being read.
  final bool loading;

  final List<ProductTileData> items;

  final void Function(Product product) onProduct;

  /// Why the catalogue could not be read, or null when it was.
  ///
  /// The till cannot sell without a catalogue, so this is not a small problem
  /// and it is not a toast: it takes the pane over, says what happened, and
  /// offers the one thing that can fix it.
  final String? error;

  /// Reads the catalogue again.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          // The page's gutter, from the shared helper, so the till's chrome
          // lines up with the dashboard's.
          padding: EdgeInsetsDirectional.only(
            start: PageGutter.of(context).left,
            end: PageGutter.of(context).right,
            top: spacing.sm,
            bottom: spacing.sm,
          ),
          // The search field and the scanner on ONE row.
          //
          // They used to be two rows — a full-width field, then a full-width
          // "Scan barcode" button under it — and on a phone that spent a
          // fifth of the screen on two controls before the cashier had seen a
          // single product. The scanner is an icon because it is an icon:
          // a camera on a till is a known gesture, and the field beside it
          // carries the search.
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onQueryChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: l10n.sellSearchProducts,
                    hintText: l10n.sellScanHintSearchProducts,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    constraints: BoxConstraints(
                      minHeight: spacing.textFieldHeight,
                    ),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.sellClearSearchTooltip,
                            icon: const Icon(Icons.clear),
                            onPressed: onClearQuery,
                          ),
                  ),
                ),
              ),
              SizedBox(width: spacing.sm),
              Semantics(
                button: true,
                label: l10n.sellScanCameraLabel,
                hint: l10n.sellScanCameraHint,
                child: OutlinedButton(
                  onPressed: scanning ? null : onScan,
                  style: OutlinedButton.styleFrom(
                    // A square, finger-sized target. The button is an icon
                    // now, so the icon has to carry the whole 48dp.
                    minimumSize: Size.square(spacing.minTapTarget),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Icon(Icons.qr_code_scanner),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: error != null
              // THE ERROR SCREEN, taking the pane over.
              //
              // Selling needs the catalogue. A till that cannot read it cannot
              // sell, and a spinner that never stops is the least honest
              // thing a till can show: it says "wait", when there is nothing
              // to wait FOR. The error says what happened, and the retry
              // button is the one thing that can fix it.
              ? ErrorStateView(
                  message: error!,
                  detail: l10n.sellCatalogueLoadFailedDetail,
                  icon: Icons.inventory_2_outlined,
                  onRetry: onRetry,
                )
              : loading
                  ? const Center(child: CircularProgressIndicator())
                  : ProductTileGrid(items: items, onTap: onProduct),
        ),
      ],
    );
  }
}

/// One line in the cart, as the pane draws it.
///
/// A value rather than the screen's own cart line: the pane is a view, and
/// what it draws is a title, a subtitle, a quantity and three actions.
class SellCartLine {
  const SellCartLine({
    required this.title,
    required this.subtitle,
    required this.quantity,
    required this.decreaseLabel,
    required this.increaseLabel,
    required this.removeLabel,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
    this.onEdit,
  });

  /// The product and its portion, as the cashier knows it.
  final String title;

  /// The size and the price.
  final String subtitle;

  /// How many, as the cashier reads it: 2, or 0.5.
  final String quantity;

  final String decreaseLabel;
  final String increaseLabel;
  final String removeLabel;

  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onRemove;
  final VoidCallback? onEdit;
}

/// The cart: what is in it, and what it costs.
class SellCartPane extends StatelessWidget {
  const SellCartPane({
    required this.lines,
    required this.itemCountLabel,
    required this.totalLabel,
    required this.emptyHint,
    required this.offlineLabel,
    required this.mpesaLabel,
    required this.onOffline,
    required this.onMpesa,
    this.onHold,
    this.onHeld,
    this.onDiscount,
    required this.processing,
    this.statusMessage,
    super.key,
  });

  final List<SellCartLine> lines;

  /// "3 items", beside the title.
  final String itemCountLabel;

  /// The total, already formatted as money.
  final String totalLabel;

  /// What the empty cart says.
  final String emptyHint;

  final String offlineLabel;
  final String mpesaLabel;

  final VoidCallback onOffline;
  final VoidCallback onMpesa;
  final VoidCallback? onHold;
  final VoidCallback? onHeld;
  final VoidCallback? onDiscount;

  /// Whether a payment is running, so the buttons are not pressed twice.
  final bool processing;

  /// The last thing that happened, said out loud and left on screen.
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: PageGutter.of(context).left,
            end: PageGutter.of(context).right,
            top: spacing.md,
            bottom: spacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (statusMessage != null)
                Semantics(
                  liveRegion: true,
                  container: true,
                  label: statusMessage,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: spacing.sm),
                    child: Text(
                      statusMessage!,
                      style: type.bodySmall,
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.sellCartTitle,
                        style: type.titleLarge,
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Text(itemCountLabel, style: type.bodySmall),
                  PopupMenuButton<String>(
                    tooltip: 'Held sales',
                    onSelected: (value) {
                      if (value == 'hold') onHold?.call();
                      if (value == 'held') onHeld?.call();
                      if (value == 'discount') onDiscount?.call();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'discount',
                        enabled: lines.isNotEmpty && onDiscount != null,
                        child: const Text('Order discount'),
                      ),
                      PopupMenuItem<String>(
                        value: 'hold',
                        enabled: lines.isNotEmpty && onHold != null,
                        child: const Text('Hold sale'),
                      ),
                      const PopupMenuItem<String>(
                          value: 'held', child: Text('Held sales')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: lines.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(spacing.lg),
                    child: Text(
                      emptyHint,
                      textAlign: TextAlign.center,
                      style: type.bodyMedium,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: spacing.sm),
                  itemCount: lines.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SellCartLine line = lines[index];
                    return ListTile(
                      onTap: line.onEdit,
                      // The name WRAPS, all the way.
                      //
                      // A product name is the cashier's typing — up to 120
                      // characters, and a shop that names its products for the
                      // shelf. The old bound here was two lines and an
                      // ellipsis, on the theory that a long name "pushed the
                      // money off the screen" — but the cart rows are their
                      // OWN scrollable. At ordinary text sizes the total and
                      // payment buttons remain below it; at enlarged text the
                      // action block itself can scroll rather than clipping.
                      //
                      // So the name is whole. A name cut in half is a product
                      // the cashier cannot find.
                      title: Text(
                        line.title,
                      ),
                      subtitle: Text(
                        // It WRAPS too, and it is never ellipsized.
                        //
                        // The subtitle carries the price — "500ml · KSh
                        // 1,240.00" — and a truncated price is a WRONG price.
                        // A number may not be cut, so the row grows instead.
                        line.subtitle,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Semantics(
                            button: true,
                            label: line.decreaseLabel,
                            child: IconButton(
                              icon: const Icon(Icons.remove),
                              tooltip: line.decreaseLabel,
                              onPressed: line.onDecrease,
                            ),
                          ),
                          Text(line.quantity, style: type.titleSmall),
                          Semantics(
                            button: true,
                            label: line.increaseLabel,
                            child: IconButton(
                              icon: const Icon(Icons.add),
                              tooltip: line.increaseLabel,
                              onPressed: line.onIncrease,
                            ),
                          ),
                          Semantics(
                            button: true,
                            label: line.removeLabel,
                            child: IconButton(
                              icon: const Icon(Icons.delete),
                              tooltip: line.removeLabel,
                              onPressed: line.onRemove,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: PageGutter.of(context).left,
                end: PageGutter.of(context).right,
                top: spacing.sm,
                bottom: spacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        l10n.sellTotalOnly,
                        style: type.titleLarge,
                      ),
                      SizedBox(width: spacing.sm),
                      // Flexible, so the amount WRAPS rather than overflowing the
                      // row: a Row hands its non-flexible children an unbounded
                      // width, and an unbounded total is a total painted past the
                      // edge of the card. The label yields; the amount does not.
                      Flexible(
                        child: Text(
                          totalLabel,
                          textAlign: TextAlign.end,
                          style: type.headlineMedium,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacing.md),
                  // THE TWO PAYMENT METHODS, SIDE BY SIDE.
                  //
                  // They were a Row before, and they stay a Row: the cart is a
                  // FIXED share of the page, and two buttons stacked are twice as
                  // tall as one. The label is not truncated to fit — it wraps
                  // instead, and the pane's share of the page grows with the text
                  // to make room (see `SellPaneLayout`).
                  //
                  // M-Pesa is the FILLED button because it is the path almost every
                  // customer takes, and it is the one green thing on the till. The
                  // offline fallback is quiet, because two saturated buttons on one
                  // screen would spend the accent twice and leave the eye with
                  // nothing to choose.
                  //
                  // `IntrinsicHeight` so both buttons are the SAME height even when
                  // one label wraps to two lines and the other does not: a row of
                  // two buttons of different heights is a row that looks broken.
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                lines.isEmpty || processing ? null : onOffline,
                            icon: const Icon(Icons.payments),
                            label: Text(offlineLabel),
                          ),
                        ),
                        SizedBox(width: spacing.sm),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                lines.isEmpty || processing ? null : onMpesa,
                            icon: const Icon(Icons.phone_iphone),
                            label: Text(mpesaLabel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
