// The deliveries history: what was received, from whom, and what it cost —
// with the owner's void directly on it.
//
// ## WHY A LIST INSTEAD OF NOTHING
//
// A purchase history is how a delivery is AUDITED: "we bought 24 crates on
// the 3rd, and the shelf shows 20 — where did four go?" Before the supplier
// and the cost went in together, the question could not even be asked.
//
// ## WHY THE VOID LIVES HERE
//
// A mistyped delivery is wrong in three ledgers at once: the stock, the cost
// and the money. Undoing it needs one deliberate action against the whole
// receipt, not a row of edit buttons, and it must be the OWNER doing it — the
// receipt's numbers are the shop's books.

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/operation_result.dart';
import '../ui/components/states.dart';
import '../ui/components/status.dart';
import '../utils/datetime_format.dart';
import '../utils/money.dart';

/// The deliveries history sheet.
class DeliveriesHistorySheet extends StatelessWidget {
  const DeliveriesHistorySheet({
    required this.receipts,
    required this.supplierNames,
    required this.canVoid,
    this.staffId,
    required this.staffName,
    super.key,
  });

  final List<StockReceipt> receipts;
  final Map<int, String> supplierNames;
  final bool canVoid;
  final int? staffId;
  final String staffName;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding:
                  EdgeInsets.fromLTRB(spacing.lg, spacing.lg, spacing.lg, 0),
              child: Text(l10n.receiveHistoryTitle, style: type.titleLarge),
            ),
            SizedBox(height: spacing.sm),
            if (receipts.isEmpty)
              Padding(
                padding: EdgeInsets.all(spacing.lg),
                child: EmptyStateView(
                  title: l10n.receiveHistoryTitle,
                  message: l10n.receiveHistoryEmpty,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: receipts.length,
                  itemBuilder: (BuildContext context, int index) {
                    return _ReceiptRow(
                      receipt: receipts[index],
                      supplierName:
                          supplierNames[receipts[index].supplierId],
                      canVoid: canVoid,
                      staffId: staffId,
                      staffName: staffName,
                    );
                  },
                ),
              ),
            SizedBox(height: spacing.md),
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.receipt,
    required this.supplierName,
    required this.canVoid,
    this.staffId,
    required this.staffName,
  });

  final StockReceipt receipt;
  final String? supplierName;
  final bool canVoid;
  final int? staffId;
  final String staffName;

  Future<void> _void(BuildContext context) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ConfirmOutcome outcome = await confirmIrreversible(
      context,
      title: l10n.receiveVoidTitle,
      message: l10n.receiveVoidMessage,
      confirmLabel: l10n.receiveVoidConfirm,
    );
    if (outcome is! ConfirmAccepted) return; // dismissed counts, too
    if (!context.mounted) return;
    try {
      await DatabaseHelper.instance.voidStockReceipt(
        receiptId: receipt.id!,
        staffName: staffName,
        staffId: staffId,
      );
      // The voided state shows on the row itself; nothing to pop over it.
    } on StateError catch (error) {
      // The shortfall — stock already sold — is the message the owner needs:
      // name it, exactly, next to the button they just pressed.
      if (!context.mounted) return;
      showOperationFailure(
        context,
        title: l10n.receiveVoidAction,
        message: l10n.receiveVoidFailed(error.message.toString()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final voided = receipt.status == 'voided';

    return ExpansionTile(
      enabled: !voided || receipt.items.isNotEmpty,
      title: Text(
        supplierName ?? l10n.receiveNoSupplier,
        style: type.bodyLarge?.copyWith(
          decoration: voided ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        formatInstant(receipt.receivedAt),
        style: type.bodySmall?.copyWith(color: colors.onSurfaceMuted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            formatMoney(receipt.totalCost),
            style: type.bodyLarge,
          ),
          if (voided) ...<Widget>[
            SizedBox(width: spacing.xs),
            StatusChip(
              tone: StatusTone.danger,
              text: l10n.receiveVoidedBy,
            ),
          ],
        ],
      ),
      children: <Widget>[
        for (final StockReceiptItem item in receipt.items)
          ListTile(
            dense: true,
            title: Text(item.productName, style: type.bodyMedium),
            trailing: Text(
              formatMoney(item.lineCost),
              style: type.bodyMedium,
            ),
            leading: Text(
              l10n.receiveQtyValue(item.qty),
              style: type.bodyMedium?.copyWith(color: colors.onSurfaceMuted),
            ),
          ),
        if (canVoid && !voided)
          Padding(
            padding: EdgeInsets.only(
                left: spacing.lg,
                right: spacing.lg,
                bottom: spacing.md),
            child: OutlinedButton.icon(
              onPressed: () => _void(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.danger,
              ),
              icon: const Icon(Icons.undo),
              label: Text(l10n.receiveVoidAction),
            ),
          ),
      ],
    );
  }
}
