// The top of the dashboard: today's date, the shop, whose takings these are, and
// the one thing a till is for.
//
// `DashboardHeader` sits above every number deliberately. The scope line is here
// rather than buried next to the totals because a cashier looking at
// KSh 48,320 needs to know whether that is the shop's money or theirs — the
// number cannot say.
//
// The Sell button is the screen's single primary action. Every other control is
// either a drill-down into a figure or a fix for a problem; "start a sale" is
// the only reason someone opens a POS.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../routing/routes.dart';
import '../services/analytics.dart';
import '../services/live_channel_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../ui/components/screen_title.dart';

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    required this.shopName,
    required this.subtitle,
    required this.onSell,
    super.key,
  });

  final String shopName;

  /// "Good morning, Wanjiku · Cashier · you" — resolved once per load by the
  /// screen, so it does not change because a rebuild happened at 17:00.
  final String subtitle;

  final VoidCallback onSell;

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    final String date =
        DateFormat.MMMMEEEEd(l10n.localeName).format(DateTime.now());

    // The title sits DIRECTLY on the canvas, large and left-aligned, the way
    // the shop's name sits at the top of the reference design.
    //
    // The brand mark used to lead this header. It does not any more: the
    // shell's bar carries the mark, and a screen that opens with a logo has
    // spent its first line on the product instead of on the shop.
    final Widget title = ScreenTitle(
      eyebrow: date.toUpperCase(),
      title: shopName,
      subtitle: subtitle,
      // The page already insets its content; the title block does not add a
      // second gutter on top of it.
      padding: EdgeInsetsDirectional.only(top: spacing.sm, bottom: spacing.xs),
    );

    // The live status, only when the channel is doing something.
    //
    // Shown under the subtitle rather than as a badge of its own, because the
    // moment it is useful is when a shop is waiting for the other terminal to
    // finish a sale. An `off` channel is not shown at all: an offline-only
    // build has no channel, and telling every such shop "not connected" is
    // noise about a state they chose.
    //
    // Watching the service rebuilds this header on every live change, which
    // is also how the dashboard itself notices one — see
    // `_DashboardScreenState.didChangeDependencies`.
    final Widget status =
        _LiveStatusLine(service: context.watch<LiveChannelService>());

    final Widget sell = FilledButton.icon(
      onPressed: onSell,
      icon: const Icon(Icons.point_of_sale_outlined, size: 18),
      label: Text(AppDestination.sell.label(l10n)),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // A phone gets the title and button stacked at full width, where a
        // thumb reaches them; anything wider puts them side by side.
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              title,
              status,
              SizedBox(height: spacing.lg),
              sell,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[title, status],
              ),
            ),
            SizedBox(width: spacing.xl),
            sell,
          ],
        );
      },
    );
  }
}

class DashboardAttentionCard extends StatelessWidget {
  const DashboardAttentionCard({
    required this.summary,
    required this.canFixEtims,
    required this.onRetryEtims,
    required this.onOpenEtimsSettings,
    this.onRetryRejectedEtims,
    this.dismissed = const <String>{},
    this.onDismiss,
    super.key,
  });

  final AttentionSummary summary;

  final bool canFixEtims;

  final VoidCallback onRetryEtims;
  final VoidCallback onOpenEtimsSettings;

  /// Puts the receipts KRA refused back in the queue.
  ///
  /// A refusal is permanent for the receipt that caused it and not for the
  /// shop: once the cause is fixed — a wrong TIN, a buyer PIN that does not
  /// verify — those invoices still have to be filed. Without this action a
  /// refusal is a dead end, and a dead end is where a shop stops complying.
  final VoidCallback? onRetryRejectedEtims;

  /// Category ids the owner has dismissed. Those rows are not shown.
  final Set<String> dismissed;

  /// Fired when the owner taps the (X) on a category, with that category's id.
  final void Function(String)? onDismiss;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<_Attention> items = <_Attention>[
      if (summary.rejectedEtims > 0)
        _Attention(
          id: 'rejectedEtims',
          count: summary.rejectedEtims,
          tone: StatusTone.danger,
          label: l10n.attentionKraRefused(summary.rejectedEtims),
          // The distinction that matters: retrying a REFUSED receipt achieves
          // nothing until the configuration is right. Sending a cashier to tap
          // Retry is sending them in circles.
          detail: l10n.attentionKraRefusedDetail,
          action: canFixEtims
              ? _AttentionAction(
                  l10n.attentionKraRefusedFixAction, onOpenEtimsSettings)
              : null,
          // Offered second, and only to the people who can fix the cause: once
          // the details are right, the refused receipts are filed without
          // anyone having to re-ring a single sale.
          secondaryAction: onRetryRejectedEtims == null
              ? null
              : _AttentionAction(
                  l10n.attentionKraRefusedRetryAction, onRetryRejectedEtims!),
        ),
      if (summary.pendingEtims > 0)
        _Attention(
          id: 'pendingEtims',
          count: summary.pendingEtims,
          tone: StatusTone.pending,
          label: l10n.attentionKraPending(summary.pendingEtims),
          detail: l10n.attentionKraPendingDetail,
          action: _AttentionAction(l10n.attentionKraRetryAction, onRetryEtims),
        ),
      if (summary.unverifiedPayments > 0)
        _Attention(
          id: 'unverifiedPayments',
          count: summary.unverifiedPayments,
          tone: StatusTone.warning,
          label: l10n.attentionUnverifiedPayments(summary.unverifiedPayments),
          detail: l10n.attentionUnverifiedPaymentsDetail,
        ),
      if (summary.openImportProblems > 0)
        _Attention(
          id: 'openImportProblems',
          count: summary.openImportProblems,
          tone: StatusTone.warning,
          label: l10n.attentionImportProblems(summary.openImportProblems),
          // The rows are answerable HERE, on the phone. The advice used to be to
          // re-import the spreadsheet — which would not have cleared them, and
          // which assumed a desktop and the supplier's file.
          detail: l10n.attentionImportProblemsDetail,
          action: _AttentionAction(l10n.attentionImportProblemsAction, () {
            context.push(Routes.imports);
          }),
        ),
    ].where((item) => !dismissed.contains(item.id)).toList();

    return SurfaceCard(
      // The one card on this screen with a filled danger container, because it is
      // the one that means money is not reconciled.
      color: AppColors.of(context).surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              StatusChip(
                tone: StatusTone.danger,
                text: AppLocalizations.of(context)
                    .attentionItemsToFix(items.length),
              ),
              SizedBox(width: AppSpacing.of(context).sm),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)
                      .attentionSectionTitleNeedsAttention,
                  style: AppTypography.of(context).titleMedium,
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.of(context).sm),
          for (int i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0)
              Divider(
                height: 1,
                color: AppColors.of(context).outline,
              ),
            _AttentionRow(
              attention: items[i],
              isFirst: i == 0,
              isLast: i == items.length - 1,
              onDismiss:
                  onDismiss == null ? null : () => onDismiss!(items[i].id),
            ),
          ],
        ],
      ),
    );
  }
}

class _Attention {
  const _Attention({
    required this.id,
    required this.count,
    required this.tone,
    required this.label,
    required this.detail,
    this.action,
    this.secondaryAction,
  });

  /// Stable category id, used with [DashboardAttentionCard.dismissed] so an
  /// owner can drop a row they have read.
  final String id;

  final int count;
  final StatusTone tone;
  final String label;
  final String detail;
  final _AttentionAction? action;

  /// A second way out of the same problem.
  ///
  /// One action per row is the usual rule, and it holds everywhere else. Here
  /// it does not: a refused receipt has TWO remedies — correct the details
  /// that KRA refused, or simply try again now that they are corrected — and
  /// offering only the first leaves the owner unable to file the invoices
  /// they have already fixed the cause for.
  final _AttentionAction? secondaryAction;
}

class _AttentionAction {
  const _AttentionAction(this.label, this.onPressed);
  final String label;
  final VoidCallback onPressed;
}

/// One problem row.
///
/// The count is in the LABEL, not only in the badge. That is deliberate: the
/// three channels are the badge's tone (glyph + word + colour) and the sentence

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.attention,
    required this.isFirst,
    required this.isLast,
    this.onDismiss,
  });

  final _Attention attention;
  final bool isFirst;
  final bool isLast;

  /// Fired when the owner taps the (X) to dismiss this category.
  final void Function()? onDismiss;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(
        top: isFirst ? 0 : spacing.md,
        bottom: isLast ? 0 : spacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: spacing.xs),
            decoration: BoxDecoration(
              color: attention.tone.container(colors),
              borderRadius: shapes.chipRadius,
              border: Border.all(color: attention.tone.color(colors)),
            ),
            child: Text(
              AppLocalizations.of(context).attentionCountBadge(attention.count),
              style: AppTypography.money(
                context,
                size: 13,
                weight: FontWeight.w700,
              ).copyWith(color: attention.tone.onContainer(colors)),
            ),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(
                  // gen-l10n sorts the parameters ALPHABETICALLY — detail,
                  // label — which is the reverse of the sentence's own order
                  // "{label}. {detail}". These were passed label-first.
                  label: AppLocalizations.of(context)
                      .attentionSpoken(attention.detail, attention.label),
                  excludeSemantics: true,
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(attention.label, style: type.titleSmall),
                        SizedBox(height: 2),
                        Text(
                          attention.detail,
                          style: type.bodySmall?.copyWith(
                            color: colors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (attention.action != null ||
              attention.secondaryAction != null) ...<Widget>[
            SizedBox(width: spacing.sm),
            // 44px tall: this is a real target on a real till, not a text link
            // pretending to be one.
            //
            // Two actions stack: side by side they would squeeze their labels
            // onto two lines on a 320dp phone, and a squashed button is a
            // button people miss.
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: spacing.minTapTarget),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (attention.action != null)
                    TextButton(
                      onPressed: attention.action!.onPressed,
                      child: Text(attention.action!.label),
                    ),
                  if (attention.secondaryAction != null)
                    TextButton(
                      onPressed: attention.secondaryAction!.onPressed,
                      child: Text(attention.secondaryAction!.label),
                    ),
                ],
              ),
            ),
          ],
          if (onDismiss != null) ...<Widget>[
            SizedBox(width: spacing.sm),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: spacing.minTapTarget),
              child: Tooltip(
                message: AppLocalizations.of(context).attentionDismissAction,
                child: IconButton(
                  tooltip: AppLocalizations.of(context).attentionDismissAction,
                  onPressed: onDismiss!,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The live channel's state, as a quiet line of text.

// screen are current, which is a fact worth having and not worth shouting.
class _LiveStatusLine extends StatelessWidget {
  const _LiveStatusLine({required this.service});

  final LiveChannelService service;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);

    return switch (service.state) {
      // The only state worth a colour: connected is good news, and the rest is
      // neutral because none of them is an error the owner caused.
      LiveConnectionState.connected => _StatusText(
          text: service.change == null
              ? l10n.liveStatusConnected
              : l10n.liveStatusUpdated(_timeAgo(service.change!.at, l10n)),
          tone: colors.success,
        ),
      LiveConnectionState.connecting =>
        _StatusText(text: l10n.liveStatusConnecting),
      LiveConnectionState.paused =>
        _StatusText(text: l10n.liveStatusReconnecting),
      // Nothing to render. See the note on the header: an offline-only build
      // has no channel, and telling every such shop "not connected" is noise
      // about a state they chose.
      LiveConnectionState.off => const SizedBox.shrink(),
    };
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.text, this.tone});

  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = AppColors.of(context);
    final TextTheme type = AppTypography.of(context);
    final Color effective = tone ?? colors.onSurfaceMuted;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: effective, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: type.labelSmall?.copyWith(color: effective),
          ),
        ],
      ),
    );
  }
}

// `DateFormat` and adding a whole relative-time locale table for one label is
// more than the label is worth. Bumped to the minute because a second-level
// figure would churn on every message.
String _timeAgo(DateTime at, AppLocalizations l10n) {
  final seconds = DateTime.now().toUtc().difference(at).inSeconds;
  if (seconds < 60) return l10n.liveStatusJustNow;
  final minutes = seconds ~/ 60;
  if (minutes < 60) return l10n.liveStatusMinutes(minutes);
  return l10n.liveStatusHours(minutes ~/ 60);
}
