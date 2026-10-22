// The portfolio view: how every shop this account runs is doing, in one place.
//
// A second shop used to mean the owner read the takings twice and added the
// figures themselves — on the device, and at the moment they were least likely
// to have signal. The backend now aggregates across the caller's own tenants,
// so this is one screen answering the question that no single shop can answer.
//
// ## What this screen is NOT for
//
// It does not rank shops against each other to shame anyone. The one figure the
// busiest shop reveals is "why the total moved", which is the question an owner
// opens this with. A shop that sold nothing is still listed, at zero, because a
// shop missing from its own owner's list reads as a shop the app has lost.
// Offline is stated as a state, not hidden: the roll-up is computed server-side
// from the ledger, so there is nothing to show without a connection, and a
// blank screen that looks like a data loss is worse than one sentence saying why.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/app_state.dart';
import '../services/backend_service.dart';
import '../services/local_portfolio_service.dart';
import '../services/portfolio_kpis.dart';
import '../services/live_refresh_mixin.dart';
import '../services/live_channel_service.dart';
import '../services/session_refresh_mixin.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_haptics.dart';
import '../theme/typography.dart';
import '../ui/components/controls.dart';
import '../ui/components/states.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../widgets/chart.dart';

enum PortfolioRange { week, month, quarter }

extension on PortfolioRange {
  DateTime since(DateTime now) => switch (this) {
        PortfolioRange.week => DateTime(now.year, now.month, now.day - 6),
        PortfolioRange.month => DateTime(now.year, now.month, now.day - 29),
        PortfolioRange.quarter => DateTime(now.year, now.month, now.day - 89),
      };
}

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen>
    with LiveRefresh<PortfolioScreen>, SessionRefresh<PortfolioScreen> {
  PortfolioRange _range = PortfolioRange.week;
  _PortfolioView _view = const _PortfolioLoading();

  bool _loading = true;

  @override
  Set<LiveReason> get liveReasons => const <LiveReason>{};

  @override
  bool get liveIsVisible => TickerMode.valuesOf(context).enabled;

  @override
  Future<void> reloadFromLive() => _load();

  @override
  void clearForSession() {
    _view = const _PortfolioLoading();
  }

  @override
  Future<void> reloadFromSession() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final PortfolioRange range = _range;
    // Whose tokens this fetch will use. A read that outlives its session has
    // to be dropped rather than painted, because these KPIs are the signed-in
    // shop's — the next person's figures must come from the next person's
    // fetch, however the two overlap.
    final int session = context.read<AppState>().sessionGeneration;
    final DateTime now = DateTime.now();
    setState(() {
      _loading = true;
      if (_view is! _PortfolioContent) _view = const _PortfolioLoading();
    });
    try {
      final PortfolioKpis kpis = await _read(range, now, session);
      if (!_current(session)) return;
      setState(() {
        _loading = false;
        _view = kpis.isEmpty
            ? const _PortfolioEmpty()
            : _PortfolioContent(kpis: kpis);
      });
    } catch (_) {
      if (!_current(session)) return;
      setState(() {
        _loading = false;
        _view = const _PortfolioFailure();
      });
    }
  }

  /// The figures, from wherever they can be had.
  ///
  /// The DEVICE FIRST. Every shop on this phone has its own database file
  /// with its own sales in it, so the screen can answer the question it was
  /// opened to answer with no connection at all — which is the normal state of
  /// a shop's till.
  ///
  /// The backend is then asked for anything the device does not have: a shop
  /// the owner runs from another phone, or one that has been online since the
  /// last sync. A shop is counted ONCE — the device's own file is the truth
  /// about the shop it holds, and the backend's copy of that same shop is
  /// skipped rather than added to it.
  Future<PortfolioKpis> _read(
    PortfolioRange range,
    DateTime now,
    int session,
  ) async {
    final DateTime from = range.since(now);
    final PortfolioKpis local =
        await LocalPortfolioService.read(from: from, to: now);

    PortfolioKpis remote = const PortfolioKpis.empty();
    try {
      remote = await BackendService.portfolioKpis(from: from, to: now);
    } catch (_) {
      // No connection, or the server said no. The device's own figures are
      // the answer, and a phone with one shop is never empty.
      if (local.shops.isEmpty) rethrow;
    }
    if (!_current(session)) return local;

    // The shops the device holds are the shops the backend also knows about,
    // in every normal case — the same shop, counted twice.
    final Set<String> held = local.shops
        .map((ShopKpi kpi) => kpi.shopName.trim().toLowerCase())
        .toSet();
    final List<ShopKpi> merged = <ShopKpi>[
      ...local.shops,
      ...remote.shops.where(
        (ShopKpi kpi) => !held.contains(kpi.shopName.trim().toLowerCase()),
      ),
    ];
    return PortfolioKpis(
      shops: merged,
      windowStart: from,
      windowEnd: now,
    );
  }

  /// Whether the session this load started under is still the session.
  bool _current(int session) =>
      mounted && context.read<AppState>().sessionGeneration == session;

  void _setRange(PortfolioRange range) {
    if (range == _range) return;
    HapticTheme.of(context).fire(HapticEvent.select);
    setState(() => _range = range);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        // The screen's NAME, not the brand lockup. The app bar is a title on
        // the canvas now — no filled band, no logo — and the brand mark lives
        // in the shell's bar.
        title: Text(l10n.portfolioTitle),
      ),
      body: AdaptivePage(
        scrollable: false,
        maxContentWidth: 880,
        child: switch (_view) {
          // A skeleton shaped like the shop rows that are about to arrive,
          // rather than a spinner over an empty box: the figure the owner came
          // for arrives as rows, so the wait looks like the rows.
          _PortfolioLoading() => const SkeletonList(itemCount: 5),
          _PortfolioFailure() => _PortfolioFailureView(onRetry: _load),
          _PortfolioEmpty() => const _PortfolioEmptyView(),
          _PortfolioContent(:final PortfolioKpis kpis) => PortfolioPanel(
              kpis: kpis,
              range: _range,
              onRangeChanged: _setRange,
              onRetry: _load,
              // Kept on screen while it reloads: a chart that blanks to a
              // spinner on every pull reads as the figures having gone, and a
              // re-read triggered by a pull needs nothing more than a spinner
              // over content that is still true.
              refreshing: _loading,
            ),
        },
      ),
    );
  }
}

/// The sealed view state, so exactly one of four renders and no boolean triple
/// can represent loading-and-error at once.
sealed class _PortfolioView {
  const _PortfolioView();
}

final class _PortfolioLoading extends _PortfolioView {
  const _PortfolioLoading();
}

final class _PortfolioFailure extends _PortfolioView {
  const _PortfolioFailure();
}

final class _PortfolioEmpty extends _PortfolioView {
  const _PortfolioEmpty();
}

final class _PortfolioContent extends _PortfolioView {
  const _PortfolioContent({required this.kpis});

  final PortfolioKpis kpis;
}

/// The view itself, built from a value and callbacks only.
class PortfolioPanel extends StatelessWidget {
  const PortfolioPanel({
    super.key,
    required this.kpis,
    required this.range,
    required this.onRangeChanged,
    required this.onRetry,
    required this.refreshing,
  });

  final PortfolioKpis kpis;
  final PortfolioRange range;
  final ValueChanged<PortfolioRange> onRangeChanged;

  /// The one reload callback: pulls the cross-shop figures again. The network
  /// read is the slowest in the app and the figures are the ones an owner
  /// checks most often after a delivery, so a shop that cannot re-read them
  /// without a round trip has to leave and come back.
  final Future<void> Function() onRetry;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    // ONE scroll view for the whole panel, header control included. Sticking a
    // range control above a separate ListView gives a Column with a scrollable
    // child and no bound, which is an unbounded-constraints crash the moment
    // the panel is nested anywhere but a viewport. Scrolling is a property of
    // the list; the header is simply the first thing in it.
    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          // The window, as a menu rather than a segmented row. Three segments
          // named "7 days", "30 days" and "90 days" fit 320dp at 1× and overflow it
          // at 2×, and the alternative — shrinking the labels — is the one thing
          // this app refuses to do. A menu therefore adapts to the text instead of
          // asking it to adapt to the row.
          //
          // The button is an `OutlinedButton`, not a `Chip`: a Material chip's
          // ink box is 34px tall, below the 44px floor, and wrapping it in a
          // `ConstrainedBox` only grows the box around the ink — the assertion
          // measures the ink. An outlined button is already 40px and grows with
          // its own label.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PopupMenuButton<PortfolioRange>(
              initialValue: range,
              onSelected: onRangeChanged,
              tooltip: l10n.portfolioRangeLabel,
              position: PopupMenuPosition.under,
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<PortfolioRange>>[
                for (final MapEntry<PortfolioRange, String> option
                    in <MapEntry<PortfolioRange, String>>[
                  MapEntry<PortfolioRange, String>(
                      PortfolioRange.week, l10n.portfolioRangeWeek),
                  MapEntry<PortfolioRange, String>(
                      PortfolioRange.month, l10n.portfolioRangeMonth),
                  MapEntry<PortfolioRange, String>(
                      PortfolioRange.quarter, l10n.portfolioRangeQuarter),
                ])
                  PopupMenuItem<PortfolioRange>(
                    value: option.key,
                    child: Row(
                      children: <Widget>[
                        Semantics(
                          // The tick is the state, and the state must be
                          // announced, not merely visible.
                          label: option.key == range
                              ? l10n.portfolioRangeCurrent
                              : '',
                          excludeSemantics: true,
                          child: option.key == range
                              ? Icon(Icons.check,
                                  size: 18, color: AppColors.of(context).accent)
                              : const SizedBox(width: 18),
                        ),
                        SizedBox(width: AppSpacing.of(context).sm),
                        Text(option.value),
                      ],
                    ),
                  ),
              ],
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(switch (range) {
                  PortfolioRange.week => l10n.portfolioRangeWeek,
                  PortfolioRange.month => l10n.portfolioRangeMonth,
                  PortfolioRange.quarter => l10n.portfolioRangeQuarter,
                }),
              ),
            ),
          ),
          // The reload indicator, inline: a reloading view is still readable,
          // and the figures on screen stay visible while the cross-shop read
          // runs — a spinner in their place would flash values the owner is
          // reading right now.
          if (refreshing)
            Padding(
              padding: EdgeInsets.only(top: spacing.sm),
              child: const LinearProgressIndicator(minHeight: 2),
            ),
          SizedBox(height: spacing.lg),
          // The whole first. An owner opens this screen to see the one number that
          // answers "how is everything going", and burying it under the per-shop
          // rows means they read three rows to derive it.
          _PortfolioTotalsCard(kpis: kpis),
          SizedBox(height: spacing.lg),
          // The comparison as a LINE-free shape: one point per shop, ranked,
          // so the busiest is visibly the busiest without a value axis to
          // read.
          if (kpis.shops.length > 1) ...<Widget>[
            PosPieChart(
              title: l10n.portfolioSharedTitle,
              slices: <PosPieSlice>[
                for (final ShopKpi shop in kpis.shopsByRevenue)
                  if (shop.revenue.minorUnits > 0)
                    PosPieSlice(
                      label: shop.shopName,
                      value: shop.revenue.minorUnits,
                      // The rank decides the tint, so the largest slice is
                      // also the strongest one and the two channels agree
                      // instead of the colour contradicting the size.
                      color: _rankColor(
                          kpis.shopsByRevenue.indexOf(shop), context),
                      valueLabel: formatMoney(shop.revenue),
                    ),
              ],
              centerLabel: l10n.portfolioTotalRevenue,
              centerValue: formatMoney(kpis.totalRevenue),
            ),
            SizedBox(height: spacing.lg),
          ],
          SectionHeader(label: l10n.portfolioShopsTitle),
          for (int i = 0; kpis.shops.length > i; i++)
            _ShopKpiRow(
              kpi: kpis.shopsByRevenue[i],
              rank: i + 1,
              share: kpis.totalRevenue.isZero
                  ? 0
                  : kpis.shopsByRevenue[i].revenue.minorUnits /
                      kpis.totalRevenue.minorUnits,
              showDivider: i != kpis.shops.length - 1,
            ),
        ],
      ),
    );
  }

  Color _rankColor(int rank, BuildContext context) {
    final AppColors colors = AppColors.of(context);
    return switch (rank) {
      0 => colors.accent,
      1 => colors.info,
      2 => colors.success,
      3 => colors.warning,
      _ => colors.outlineStrong,
    };
  }
}

class _PortfolioTotalsCard extends StatelessWidget {
  const _PortfolioTotalsCard({required this.kpis});

  final PortfolioKpis kpis;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.portfolioTotalRevenue,
              style: AppTypography.of(context).bodySmall?.copyWith(
                    color: AppColors.of(context).onSurfaceMuted,
                  )),
          SizedBox(height: spacing.xs),
          // Tabular figures: a figure that shifts sideways as its digits change
          // cannot be compared against anything, and this is the number every
          // other figure on the screen is measured against.
          MoneyText(
            amount: formatMoney(kpis.totalRevenue),
            size: 28,
            weight: FontWeight.w700,
          ),
          SizedBox(height: spacing.sm),
          // Stacked, not three-in-a-row. Three `KeyValueRow`s side by side give
          // each one a third of 320dp, and at 2.0× text the labels "Avg basket"
          // and "Profit" no longer fit a third of the width — the row overflows
          // rather than shrinking, because shrinking a label is the one thing
          // this app refuses to do.
          KeyValueRow(
            label: l10n.portfolioProfit,
            value: formatMoney(kpis.totalProfit),
          ),
          KeyValueRow(
            label: l10n.portfolioTransactions,
            value: kpis.totalTransactions.toString(),
          ),
          KeyValueRow(
            label: l10n.portfolioAvgBasket,
            value: formatMoney(kpis.averageBasket),
          ),
          SizedBox(height: spacing.sm),
          // Where the total came from. A total is a number an owner cannot act
          // on; a total plus its source is the thing they open next.
          if (kpis.topShopByRevenue != null)
            Semantics(
              liveRegion: true,
              child: Row(
                children: <Widget>[
                  // The same arrow, size and tone a `StatTile` delta uses: an
                  // up arrow in the success tone, so "the busiest shop" reads
                  // as the same kind of up as every other rise in the app and
                  // the word beside it says which shop it is.
                  ExcludeSemantics(
                    child: Icon(
                      Icons.arrow_upward,
                      size: 14,
                      color: AppColors.of(context).success,
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(
                      l10n.portfolioTopShop(
                        formatMoney(kpis.topShopByRevenue!.revenue),
                        kpis.topShopByRevenue!.shopName,
                      ),
                      style: AppTypography.of(context).bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ShopKpiRow extends StatelessWidget {
  const _ShopKpiRow({
    required this.kpi,
    required this.rank,
    required this.share,
    required this.showDivider,
  });

  final ShopKpi kpi;
  final int rank;
  final double share;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    // A percentage pattern rather than a hand-rolled '34%': intl knows whether
    // this locale writes the percent sign before or after the figure, and a
    // spliced '%' is wrong in more than one of them.
    final NumberFormat percent = NumberFormat.percentPattern(
      Localizations.localeOf(context).toString(),
    );

    final Widget row = Padding(
      padding: EdgeInsetsDirectional.only(
        top: spacing.md,
        bottom: spacing.md,
      ),
      child: Row(
        children: <Widget>[
          // A round tonal badge on the leading edge: a marker, the way every
          // other row in this app is marked. The rank beside it is the fact —
          // 1st is the number, not a medal, and a screen reader can use it.
          const IconBadge(icon: Icons.storefront_outlined),
          SizedBox(width: spacing.sm),
          ExcludeSemantics(
            child: SizedBox(
              width: 24,
              child: Text(
                '#$rank',
                style: AppTypography.of(context)
                    .titleSmall
                    ?.copyWith(color: colors.onSurfaceMuted),
                textAlign: TextAlign.end,
              ),
            ),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(kpi.shopName, style: AppTypography.of(context).bodyLarge),
                SizedBox(height: 2),
                Text(
                  '${formatMoney(kpi.revenue)} · ${percent.format(share)}',
                  style: AppTypography.of(context)
                      .bodySmall
                      ?.copyWith(color: colors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          SizedBox(width: spacing.sm),
          MoneyText(amount: formatMoney(kpi.profit), size: 13),
        ],
      ),
    );

    return Semantics(
      container: true,
      // Alphabetical, as gen-l10n orders the generated parameters: count,
      // profit, revenue, share, shop. l10n.dart documents that these getters
      // are positional by design.
      label: l10n.portfolioShopRowSpoken(
        kpi.transactions,
        formatMoney(kpi.profit),
        formatMoney(kpi.revenue),
        percent.format(share),
        kpi.shopName,
      ),
      excludeSemantics: true,
      child: ExcludeSemantics(
        child: showDivider
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  row,
                  Divider(height: 1, color: colors.outline),
                ],
              )
            : row,
      ),
    );
  }
}

class _PortfolioEmptyView extends StatelessWidget {
  const _PortfolioEmptyView();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return EmptyStateView(
      title: l10n.portfolioEmptyTitle,
      message: l10n.portfolioEmptyMessage,
    );
  }
}

class _PortfolioFailureView extends StatelessWidget {
  const _PortfolioFailureView({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ErrorStateView(
      message: l10n.portfolioFailureMessage,
      onRetry: () {
        onRetry();
      },
    );
  }
}
