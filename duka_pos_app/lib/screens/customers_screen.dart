// The customers, and what they owe (feature 7).
//
// ## WHY THIS SCREEN EXISTS
//
// A credit sale is a PROMISE — and today the app keeps promises nowhere:
// nothing remembers who owes, nothing records a repayment, and the till's
// "credit" is a paper note behind the shop's own payroll books. This screen
// is the promise's ledger: the balance, the limit, the history, and the two
// acts that change the debt (a sale taken, a payment received).
//
// ## THE ONE NUMBER THAT MATTERS
//
// The header's "owed to you" is the sum of the customers' balances, and each
// balance is a CACHE of the append-only ledger (models/credit.dart). The
// screen never edits a balance directly: adjust, write-off and repay are all
// ledger writes, because a correction that leaves no ledger row is a guess
// with a number on it.

import 'dart:async';

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/credit.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import 'package:provider/provider.dart';

import '../screens/customer_credit_sheets.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../ui/components/operation_result.dart';
import '../ui/components/states.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/status.dart';
import '../utils/money.dart';

/// Opens the customers screen (a modal takes the whole till page? — no: a
/// normal route keeps the back gesture the shop already uses).
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final TextEditingController _search = TextEditingController();
  List<Customer> _customers = const <Customer>[];
  ({int totalOwedMinor, int customerCount})? _summary;
  Map<DebtAgeBucket, ({int amountMinor, int customers, int overdueCount})>
      _aging = const <DebtAgeBucket,
          ({int amountMinor, int customers, int overdueCount})>{};
  bool _loading = true;
  String? _error;
  bool _owesOnly = false;
  String _sort = 'balance';

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = DatabaseHelper.instance;
      final results = await Future.wait<Object>(<Future<Object>>[
        db.getCustomers(
          search: _search.text,
          owesOnly: _owesOnly,
          sort: _sort,
        ),
        db.creditSummary(),
        db.creditAging(),
      ]);
      if (!mounted) return;
      setState(() {
        _customers = results[0] as List<Customer>;
        _summary =
            results[1] as ({int totalOwedMinor, int customerCount});
        _aging = results[2] as Map<
            DebtAgeBucket,
            ({int amountMinor, int customers, int overdueCount})>;
        _loading = false;
      });
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message.toString();
      });
    }
  }

  /// The search is DEBOUNCED: a customer list is scanned by the name's first
  /// letters, and a search firing per keystroke would put a query between
  /// every letter typed.
  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _load);
  }

  Future<void> _openDetail(Customer customer) async {
    final state = context.read<AppState>();
    final bool canManageCredit =
        state.isOwnerSession || state.role == ShopRole.manager;
    final bool changed = await showCustomerDetailSheet(
      context,
      customer,
      editable: canManageCredit,
    );
    if (changed && mounted) await _load();
  }

  Future<void> _addCustomer() async {
    final Customer? created = await showCustomerEditSheet(context, null);
    if (created == null || !mounted) return;
    await _load();
    if (!mounted) return;
    showOperationSuccess(
      context,
      title: AppLocalizations.of(context).customerSavedTitle,
      message: AppLocalizations.of(context).customerAddedMessage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppShapes shapes = AppShapes.of(context);
    final TextTheme type = AppTypography.of(context);
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.customersTitle)),
      floatingActionButton: FloatingActionButton.extended(
        // manage_customers: THE OWNER AND MANAGER add freely; a cashier may
        // add one mid-sale from the payment picker, not from here.
        onPressed: state.isOwnerSession || state.role == ShopRole.manager
            ? _addCustomer
            : null,
        tooltip: l10n.customerAddAction,
        isExtended: state.isOwnerSession || state.role == ShopRole.manager,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.person_add_alt_1),
            if (state.isOwnerSession || state.role == ShopRole.manager)
              SizedBox(width: spacing.xs),
            if (state.isOwnerSession || state.role == ShopRole.manager)
              Text(l10n.customerAddAction),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: <Widget>[
            // THE SUMMARY: what the shop is owed, and who owes it — one
            // "owed to you" banner, with the aging beneath it.
            Padding(
              padding: EdgeInsets.all(spacing.md),
              child: Card(
                shape: shapes.card(colors),
                child: Padding(
                  padding: EdgeInsets.all(spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.creditOwedToYou,
                        style: type.labelLarge
                            ?.copyWith(color: colors.onSurfaceMuted),
                      ),
                      Text(
                        _summary == null
                            ? '—'
                            : formatMoney(Money.fromMinor(
                                _summary!.totalOwedMinor)),
                        style: type.headlineMedium,
                      ),
                      Text(
                        l10n.creditOwedByCount(_summary?.customerCount ?? 0),
                        style: type.bodySmall
                            ?.copyWith(color: colors.onSurfaceMuted),
                      ),
                      SizedBox(height: spacing.sm),
                      // The aging: one row of four buckets, oldest judged
                      // first. Status is ICON + WORD, not colour alone.
                      // The aging: the four buckets, oldest last. A bucket
                      // is named by its window; the figures speak for it.
                      Row(
                        children: <Widget>[
                          for (final (DebtAgeBucket bucket, String label)
                              in <(DebtAgeBucket, String)>[
                            (DebtAgeBucket.upTo7Days, l10n.creditAging7),
                            (DebtAgeBucket.upTo30Days, l10n.creditAging30),
                            (DebtAgeBucket.upTo60Days, l10n.creditAging60),
                            (DebtAgeBucket.over60Days, l10n.creditAgingOver),
                          ])
                            Expanded(
                              child: Padding(
                                padding: EdgeInsetsDirectional.only(
                                    end: spacing.xs),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      label,
                                      style: type.labelLarge?.copyWith(
                                          color: colors.onSurfaceMuted),
                                    ),
                                    Text(
                                      '${_aging[bucket]?.customers ?? 0}',
                                      style: type.titleMedium,
                                    ),
                                    Text(
                                      formatMoney(Money.fromMinor(
                                          _aging[bucket]?.amountMinor ?? 0)),
                                      style: type.bodySmall?.copyWith(
                                          color: colors.onSurfaceMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // SEARCH + FILTERS.
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.md),
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10n.customerSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            _load();
                          },
                        ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.md),
              child: Row(
                children: <Widget>[
                  FilterChip(
                    selected: _owesOnly,
                    onSelected: (bool value) {
                      setState(() => _owesOnly = value);
                      _load();
                    },
                    label: Text(l10n.customersFilterOwes),
                  ),
                  SizedBox(width: spacing.xs),
                  FilterChip(
                    selected: _sort == 'name',
                    onSelected: (bool value) {
                      setState(() => _sort = value ? 'name' : 'balance');
                      _load();
                    },
                    label: Text(l10n.customersSortName),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.sm),
            if (_loading)
              Padding(
                padding: EdgeInsets.all(spacing.lg),
                child: const Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: EdgeInsets.all(spacing.lg),
                child: ErrorStateView(
                  message: _error!,
                  onRetry: _load,
                ),
              )
            else if (_customers.isEmpty && _search.text.isEmpty)
              // THE EMPTY: an empty list here is not a pity message — it is
              // the shop's first credit account being described.
              Padding(
                padding: EdgeInsets.all(spacing.lg),
                child: EmptyStateView(
                  title: l10n.customersEmptyTitle,
                  message: l10n.customersEmptyMessage,
                  actionLabel: (state.isOwnerSession || state.role == ShopRole.manager)
                      ? l10n.customerAddAction
                      : null,
                  onAction: (state.isOwnerSession || state.role == ShopRole.manager)
                      ? _addCustomer
                      : null,
                ),
              )
            else if (_customers.isEmpty)
              Padding(
                padding: EdgeInsets.all(spacing.lg),
                child: EmptyStateView(
                  title: l10n.customersNoMatchesTitle,
                  message: l10n.customersNoMatchesMessage,
                ),
              )
            else
              ..._customers.map(
                (Customer customer) => ListTile(
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: spacing.md),
                  title: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          customer.name,
                          style: type.bodyLarge?.copyWith(
                            decoration: customer.active
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                      // THE BALANCE CHIP: owed (or in credit) at a glance,
                      // word + figure, never colour alone.
                      if (customer.balanceMinor != 0)
                        StatusChip(
                          tone: customer.balanceMinor > 0
                              ? StatusTone.warning
                              : StatusTone.success,
                          text: customer.balanceMinor > 0
                              ? l10n.customerOwesChip(
                                  formatMoney(Money.fromMinor(
                                      customer.balanceMinor)))
                              : l10n.customerCreditChip(
                                  formatMoney(Money.fromMinor(
                                      -customer.balanceMinor))),
                        ),
                    ],
                  ),
                  subtitle: customer.phoneDisplay == null
                      ? null
                      : Text(customer.phoneDisplay!,
                          style: type.bodySmall
                              ?.copyWith(color: colors.onSurfaceMuted)),
                  onTap: () => _openDetail(customer),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
