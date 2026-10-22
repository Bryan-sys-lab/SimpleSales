// The details of one sale.
//
// A ledger row is a SUMMARY: an amount, a relative time, a method. It is what
// a shopkeeper scans down to answer "did we take it" and it is deliberately
// quiet.
//
// But a question like "what happened at 14:32" cannot be answered by a
// summary, and the answer to it is in fields the row does not show: the exact
// time, which till it was rung on, how the money moved, and WHO rang it. So
// every row opens.
//
// WHAT IS HERE, AND WHY EACH THING
//
//   * WHEN  — the exact instant, not "2 hours ago". A relative time is the
//     right thing in a list you scan and the wrong thing in a record you are
//     asked about.
//   * WHERE — the shop the sale was rung in. A till can be shared, and a sale
//     is only accountable against a place as well as a person.
//   * HOW   — the method, and what actually moved: the M-Pesa reference, or
//     the cash tendered and the change given. "Cash" alone does not say
//     whether the drawer balanced.
//   * WHO   — the member of staff who rang it, and the audit line that
//     recorded it. Two names, because they are two different claims: the sale
//     says who rang it, the audit says who wrote it down.
//   * WHAT  — the lines. A total with no lines is a figure a shopkeeper cannot
//     check against the shelf.
//
// The sheet is a MODAL, not a route: it is a detail OF a row, and it is
// dismissed by putting it away. The app's own routing is go_router, and this
// deliberately does not push a route for a thing that is a panel over a list.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/audit_log.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/operation_result.dart';
import '../utils/datetime_format.dart';
import '../screens/return_sale_sheet.dart';
import '../utils/money.dart';

/// Shows the details of [sale].
///
/// [canSeeSellers] governs the WHO line: a role that may not read the ledger
/// must not get the seller's name out of it by tapping a row.
Future<void> showSaleDetails(
  BuildContext context, {
  required Sale sale,
  AuditLogEntry? audit,
  required bool canSeeSellers,
  required String shopName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // The sheet is scrollable: a sale with twenty lines does not fit on a
    // phone, and a detail that cannot be read is worse than no detail.
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => _SaleDetailsSheet(
      sale: sale,
      audit: audit,
      canSeeSellers: canSeeSellers,
      shopName: shopName,
    ),
  );
}

class _SaleDetailsSheet extends StatelessWidget {
  const _SaleDetailsSheet({
    required this.sale,
    required this.audit,
    required this.canSeeSellers,
    required this.shopName,
  });

  final Sale sale;
  final AuditLogEntry? audit;
  final bool canSeeSellers;

  /// The shop the sale was rung in.
  ///
  /// Passed IN rather than read from the session: a sheet is a leaf, and a leaf
  /// that reads the session is a leaf that cannot be rendered from constructed
  /// values — which is how the record ends up untested.
  final String shopName;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final TextTheme type = AppTypography.of(context);

    final DateTime? at = DateTime.tryParse(sale.createdAt)?.toLocal();
    final String when = at == null
        ? sale.createdAt
        : formatInstant(
            sale.createdAt,
            locale: Localizations.localeOf(context).toString(),
          );

    return SafeArea(
      child: ConstrainedBox(
        // Most of the sheet, and never more than the screen: a sheet that
        // covers the whole screen is a page, and a page does not get a drag
        // handle.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: spacing.lg,
              end: spacing.lg,
              top: spacing.md,
              bottom: spacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // The amount is the headline: the number the whole sheet is
                // about.
                Text(
                  formatMoney(sale.total),
                  style: type.displaySmall?.copyWith(color: colors.onSurface),
                ),
                SizedBox(height: spacing.xs),
                Text(
                  l10n.saleDetailsTitle,
                  style: type.bodyMedium?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
                SizedBox(height: spacing.lg),

                _DetailRow(
                  icon: Icons.schedule_outlined,
                  label: l10n.saleDetailsWhen,
                  value: when,
                ),
                if (shopName.isNotEmpty)
                  _DetailRow(
                    icon: Icons.storefront_outlined,
                    label: l10n.saleDetailsWhere,
                    value: shopName,
                  ),
                _DetailRow(
                  icon: Icons.payments_outlined,
                  label: l10n.saleDetailsHow,
                  value: l10n.transactionsMethod(sale.paymentMethod),
                  // What actually moved, under the method: the provider's
                  // reference for a mobile money sale, and the money in and
                  // the money back for a cash one.
                  detail: _paymentDetail(context),
                ),
                if (canSeeSellers)
                  _DetailRow(
                    icon: Icons.person_outline,
                    label: l10n.saleDetailsWho,
                    value: sale.staffName,
                    // The audit line is a SECOND claim about who did this, and
                    // it is worth showing beside the first: the sale says who
                    // rang it, the audit says who wrote it down.
                    detail: audit == null
                        ? null
                        : l10n.transactionsAuditBy(audit!.actorName),
                  ),
                SizedBox(height: spacing.md),

                // WHAT WAS SOLD.
                //
                // The lines, so a total can be checked against the shelf. A
                // sale with no lines still shows the heading and says so,
                // because an empty list here is a fact about the record, not
                // an absence of one.
                Text(
                  l10n.saleDetailsWhat,
                  style: type.titleMedium,
                ),
                SizedBox(height: spacing.sm),
                if (sale.items.isEmpty)
                  Text(
                    l10n.saleDetailsNoItems,
                    style: type.bodyMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceSunken,
                      borderRadius: shapes.cardRadius,
                    ),
                    padding: EdgeInsets.all(spacing.md),
                    child: Column(
                      children: <Widget>[
                        for (final SaleItem item in sale.items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _SaleLineRow(item: item),
                          ),
                      ],
                    ),
                  ),
                SizedBox(height: spacing.md),
                // WHAT CAME BACK, and the button that gives something back.
                _ReturnSection(sale: sale),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// What moved, under the method.
  String? _paymentDetail(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String reference = sale.paymentReference ?? '';
    if (reference.isNotEmpty) {
      return l10n.saleDetailsReference(reference);
    }
    // Cash: what was handed over and what came back. A cash sale with no
    // tendered figure recorded says nothing rather than showing a zero the
    // shopkeeper would have to interpret.
    if (sale.amountTendered.minorUnits <= 0) return null;
    return l10n.saleDetailsTendered(
      formatMoney(sale.amountTendered),
      formatMoney(sale.changeGiven),
    );
  }
}

/// One labelled fact: an icon, a label, a value, and an optional second line.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String value;

  /// A second line under the value, for the fact that qualifies it.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: colors.onSurfaceMuted),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: type.labelMedium?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: type.bodyLarge),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: type.bodySmall?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the sale: what, how many, and what it came to.
class _SaleLineRow extends StatelessWidget {
  const _SaleLineRow({required this.item});

  final SaleItem item;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    final double qty = item.qty;
    final String quantity = qty == qty.roundToDouble()
        ? qty.toStringAsFixed(0)
        : qty.toStringAsFixed(2);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            item.productName,
            style: type.bodyMedium,
            // A product name is the cashier's typing and it can be long: it
            // WRAPS, because a name cut in half is a product the shopkeeper
            // cannot check against the shelf.
          ),
        ),
        SizedBox(width: spacing.sm),
        Text(
          l10n.saleDetailsQuantity(quantity),
          style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
        ),
        SizedBox(width: spacing.md),
        MoneyText(amount: formatMoney(item.total), size: 14),
      ],
    );
  }
}

/// The button that gives something back.
///
/// ## WHY IT DOES NO READING
///
/// A widget that reads the database while it is building itself does its I/O
/// in the middle of a build — slow, and untestable, because a query in an
/// initState cannot be awaited by anything. The figures the return flow needs
/// are read by the CALLER, at the moment the flow is opened, which is a
/// moment a person asked for.
///
/// So this is a button and nothing else.
class _ReturnSection extends StatelessWidget {
  const _ReturnSection({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(height: spacing.sm),
        OutlinedButton.icon(
          onPressed: () => _startReturn(context),
          icon: const Icon(Icons.undo_outlined),
          label: Text(l10n.returnTitle),
        ),
      ],
    );
  }

  /// Opens the return flow, with the figures it needs already read.
  Future<void> _startReturn(BuildContext context) async {
    final AppState state = context.read<AppState>();
    final int? saleId = sale.id;
    if (saleId == null) return;
    // Read BEFORE the sheet opens: an await between reading the context and
    // using it is a context used across an async gap.
    final Map<int, double> alreadyReturned =
        await DatabaseHelper.instance.getReturnedQuantitiesForSale(saleId);
    if (!context.mounted) return;
    final int? returnId = await showReturnSheet(
      context,
      sale: sale,
      staffName: state.currentStaffName ?? '',
      staffId: state.currentStaffId,
      alreadyReturned: alreadyReturned,
    );
    if (returnId == null || !context.mounted) return;
    // The outcome is a POPUP, not a screen: the till is not blocked.
    showOperationSuccess(
      context,
      title: AppLocalizations.of(context).returnTitle,
      message: AppLocalizations.of(context).returnDone,
    );
  }
}
