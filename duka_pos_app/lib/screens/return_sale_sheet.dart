// Giving a sale back.
//
// ## WHAT THIS IS
//
// "Let staff reverse part or all of a sale: restore stock, refund the customer,
// and issue a KRA credit note."
//
// The flow is three questions, asked in this order because that is the order
// they have to be answered in:
//
//   1. WHICH LINES, and how much of each. A customer who changes their mind
//      about one bottle does not bring the whole sale back, and the stepper is
//      limited by what has NOT already been returned — a bottle can come back
//      once, and the second time round there is nothing to return.
//   2. WHY, and what happens to the goods. The reason is the shop's record of
//      why the money went back; the restock choice is the difference between a
//      bottle on the shelf and a broken bottle in the bin.
//   3. HOW the money goes back, and how much. The default is the way the
//      customer paid, because that is what they expect.
//
// ## WHY IT IS A SHEET AND NOT A ROUTE
//
// It is a panel over the sale it belongs to, and it is dismissed by putting it
// away. The app's own routing is go_router, and this deliberately does not
// push a route for a thing that is a panel over a list.
//
// ## WHY THE SHEET DOES NO READING OF ITS OWN
//
// The figures it needs — how much of each line has already come back — are
// passed IN. A sheet that reads the database while it is building itself does
// its I/O in the middle of a build, which is slow, untestable, and (in a
// widget test) a hang, because a query in a widget's initState cannot be
// awaited by anything.
//
// ## WHY THE SUCCESS IS A POPUP
//
// The rest of the app does not block the till with a success screen. A
// confirmation that covers the screen is a screen the shopkeeper has to
// dismiss before they can sell the next thing — and a return is a thing that
// happens in the middle of a queue.

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/status.dart';
import '../utils/money.dart';

/// Opens the return flow for [sale].
///
/// Returns the id of the return that was recorded, or null when the person
/// put the sheet away.
Future<int?> showReturnSheet(
  BuildContext context, {
  required Sale sale,
  required String staffName,
  int? staffId,
  Map<int, double> alreadyReturned = const <int, double>{},
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => ReturnSaleSheet(
      sale: sale,
      staffName: staffName,
      staffId: staffId,
      alreadyReturned: alreadyReturned,
    ),
  );
}

/// The return flow.
class ReturnSaleSheet extends StatefulWidget {
  const ReturnSaleSheet({
    required this.sale,
    required this.staffName,
    this.staffId,
    this.alreadyReturned = const <int, double>{},
    super.key,
  });

  final Sale sale;
  final String staffName;
  final int? staffId;

  /// How much of each line has ALREADY come back, by sale line id.
  ///
  /// Passed IN rather than read here — see the file's own note.
  final Map<int, double> alreadyReturned;

  @override
  State<ReturnSaleSheet> createState() => _ReturnSaleSheetState();
}

class _ReturnSaleSheetState extends State<ReturnSaleSheet> {
  /// How much of each line is coming back, by sale line id.
  final Map<int, double> _quantities = <int, double>{};

  /// Which lines go back on the shelf, by sale line id.
  final Map<int, bool> _restock = <int, bool>{};

  final TextEditingController _reason = TextEditingController();

  String _refundMethod = 'cash';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refundMethod = widget.sale.paymentMethod == 'mpesa' ? 'mpesa' : 'cash';
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// How much of this line has not come back yet.
  double _remaining(SaleItem item) {
    final double already = widget.alreadyReturned[item.id ?? 0] ?? 0;
    final double left = item.qty - already;
    return left < 0 ? 0 : left;
  }

  /// The money to give back, in minor units.
  ///
  /// The SUM of the line refunds — each line's total scaled by the fraction
  /// coming back, rounded half-up. Not the sale's total scaled, because the
  /// two can differ by a cent and the lines are what the customer is being
  /// refunded for.
  int get _refundTotalMinor {
    int total = 0;
    for (final SaleItem item in widget.sale.items) {
      final double qty = _quantities[item.id ?? 0] ?? 0;
      if (qty <= 0) continue;
      final int lineTotal = (item.unitPrice.minorUnits * item.qty).round();
      total += (lineTotal * (qty / item.qty)).round();
    }
    return total;
  }

  bool get _hasLines => _quantities.values.any((double q) => q > 0);

  Future<void> _save() async {
    if (!_hasLines) {
      setState(() => _error = AppLocalizations.of(context).returnNoLines);
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(
          () => _error = AppLocalizations.of(context).returnReasonRequired);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final int returnId = await DatabaseHelper.instance.recordReturn(
        sale: widget.sale,
        lines: <ReturnLineDraft>[
          for (final SaleItem item in widget.sale.items)
            if ((_quantities[item.id ?? 0] ?? 0) > 0)
              ReturnLineDraft(
                saleItemId: item.id!,
                qty: _quantities[item.id]!,
                restock: _restock[item.id] ?? true,
              ),
        ],
        reason: _reason.text,
        refundMethod: _refundMethod,
        staffName: widget.staffName,
        staffId: widget.staffId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(returnId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _messageFor(error);
      });
    }
  }

  /// What to say about a refusal.
  ///
  /// The refusal is a STATE, and each one has its own sentence: a cashier
  /// who is told "something went wrong" cannot act, and the states here are
  /// the ones a person can do something about.
  String _messageFor(Object error) {
    final String text = error.toString();
    if (text.contains('no drawer') || text.contains('Open a shift')) {
      return AppLocalizations.of(context).returnNoShiftOpen;
    }
    if (text.contains('never confirmed')) {
      return AppLocalizations.of(context).returnUnverifiedPayment;
    }
    if (text.contains('More was returned')) {
      return AppLocalizations.of(context).returnMoreThanSold;
    }
    if (text.contains('not on the sale')) {
      return AppLocalizations.of(context).returnLineGone;
    }
    return AppLocalizations.of(context).returnFailed;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final TextTheme type = AppTypography.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        // ONE scroll view for the whole sheet.
        //
        // A sheet with a scrolling middle and a fixed footer has to fit its
        // footer, and at twice the text size on a small phone the footer is
        // taller than the space the middle was given — and the sheet
        // overflows. One scroll view and one column cannot: the content is
        // either taller than the sheet, in which case it scrolls, or it is
        // shorter, in which case it does not.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding:
                    EdgeInsets.fromLTRB(spacing.lg, spacing.lg, spacing.lg, 0),
                child: Text(l10n.returnTitle, style: type.titleLarge),
              ),
              SizedBox(height: spacing.xs),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: Text(
                  l10n.returnSubtitle,
                  style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
                ),
              ),
              SizedBox(height: spacing.md),

              // THE LINES.
              for (final SaleItem item in widget.sale.items)
                _ReturnLineRow(
                  item: item,
                  remaining: _remaining(item),
                  qty: _quantities[item.id ?? 0] ?? 0,
                  restock: _restock[item.id ?? 0] ?? true,
                  onChanged: (double value) => setState(() {
                    _quantities[item.id ?? 0] = value;
                    _restock[item.id ?? 0] = _restock[item.id] ?? true;
                  }),
                  onRestockChanged: (bool value) => setState(() {
                    _restock[item.id ?? 0] = value;
                  }),
                ),
              SizedBox(height: spacing.md),

              // WHY.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: TextField(
                  controller: _reason,
                  decoration: InputDecoration(
                    labelText: l10n.returnReasonLabel,
                    hintText: l10n.returnReasonHint,
                  ),
                  maxLines: 2,
                ),
              ),
              SizedBox(height: spacing.md),

              // HOW THE MONEY GOES BACK.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l10n.returnMethodLabel, style: type.labelLarge),
                    SizedBox(height: spacing.xs),
                    SegmentedButton<String>(
                      segments: <ButtonSegment<String>>[
                        ButtonSegment<String>(
                          value: 'cash',
                          label: Text(l10n.returnMethodCash),
                        ),
                        ButtonSegment<String>(
                          value: 'mpesa',
                          label: Text(l10n.returnMethodMpesa),
                        ),
                      ],
                      selected: <String>{_refundMethod},
                      onSelectionChanged: (Set<String> selection) =>
                          setState(() => _refundMethod = selection.first),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...<Widget>[
                SizedBox(height: spacing.md),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                  child: PersistentBanner(
                    tone: StatusTone.danger,
                    icon: Icons.cancel_outlined,
                    message: _error!,
                  ),
                ),
              ],
              SizedBox(height: spacing.lg),

              // THE REVIEW, and the button.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: shapes.cardRadius,
                  ),
                  padding: EdgeInsets.all(spacing.md),
                  // A WRAP, not a row: at twice the text size the button's
                  // label is wider than the phone, and a row would push the
                  // amount off the screen. A wrap drops the button onto its
                  // own line instead.
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: spacing.md,
                    runSpacing: spacing.sm,
                    children: <Widget>[
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(l10n.returnRefundLabel,
                                style: type.bodyMedium),
                            Text(
                              formatMoney(Money.fromMinor(_refundTotalMinor)),
                              style: type.titleLarge,
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(l10n.returnConfirmAction),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: spacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of the return: how much of it, and what happens to it.
class _ReturnLineRow extends StatelessWidget {
  const _ReturnLineRow({
    required this.item,
    required this.remaining,
    required this.qty,
    required this.restock,
    required this.onChanged,
    required this.onRestockChanged,
  });

  final SaleItem item;

  /// How much of it has not come back yet.
  final double remaining;

  /// How much is coming back now.
  final double qty;

  /// Whether it goes back on the shelf.
  final bool restock;

  final ValueChanged<double> onChanged;
  final ValueChanged<bool> onRestockChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    final bool soldOut = remaining <= 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.lg, 0, spacing.lg, spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(item.productName, style: type.bodyLarge),
              ),
              // How much came back already, and how much is left.
              Text(
                soldOut
                    ? l10n.returnLineAllReturned
                    : l10n.returnLineRemaining(remaining),
                style: type.bodySmall?.copyWith(
                  color: soldOut ? colors.danger : colors.onSurfaceMuted,
                ),
              ),
            ],
          ),
          if (!soldOut) ...<Widget>[
            SizedBox(height: spacing.xs),
            // The stepper, limited by what is left.
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: qty > 0
                      ? () => onChanged(qty - 1 < 0 ? 0 : qty - 1)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: l10n.returnLessAction,
                ),
                Expanded(
                  child: Text(
                    '${_formatQty(qty)} of ${_formatQty(item.qty)}',
                    style: type.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  onPressed:
                      qty + 1 > remaining ? null : () => onChanged(qty + 1),
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: l10n.returnMoreAction,
                ),
              ],
            ),
            // What happens to the goods.
            Row(
              children: <Widget>[
                Checkbox(
                  value: restock,
                  onChanged: (bool? value) => onRestockChanged(value ?? true),
                ),
                Expanded(
                  child: Text(
                    restock
                        ? l10n.returnRestockLabel
                        : l10n.returnWriteOffLabel,
                    style: type.bodyMedium?.copyWith(
                      color: restock ? colors.onSurface : colors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// A quantity, without a trailing ".0" on the whole numbers.
  static String _formatQty(double qty) {
    if (qty == qty.roundToDouble()) return qty.round().toString();
    return qty.toStringAsFixed(2);
  }
}
