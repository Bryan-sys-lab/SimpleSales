import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/credit.dart';
import '../models/layby.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';
import '../utils/money.dart';
import '../widgets/backup_reminder_banner.dart';

const double _laybyScreenMaxWidth = 1200;

/// Fashion's lay-by desk with variant-aware selection and multi-method payments.
///
/// Each layby reserves a specific variant (colour + size) so stock can't be
/// sold twice. Payments support cash, M-Pesa and bank transfer with references.
class LaybyScreen extends StatefulWidget {
  const LaybyScreen({super.key});

  @override
  State<LaybyScreen> createState() => _LaybyScreenState();
}

class _LaybyScreenState extends State<LaybyScreen> {
  final _db = DatabaseHelper.instance;
  final _qtyCtrl = TextEditingController(text: '1');
  final _depositCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _dueDaysCtrl = TextEditingController(text: '30');

  List<Customer> _customers = const [];
  List<Product> _products = const [];
  List<ProductVariant> _variants = const [];
  List<Layby> _laybys = const [];

  Customer? _customer;
  Product? _product;
  ProductVariant? _variant;

  String _depositMethod = 'cash';
  bool _saving = false;

  String get _staffName =>
      context.read<AppState>().currentStaffName ?? 'Current staff';
  int? get _staffId => context.read<AppState>().currentStaffId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _depositCtrl.dispose();
    _referenceCtrl.dispose();
    _dueDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await Future.wait([
        _db.getCustomers(sort: 'name').then((c) {
          if (!mounted) return;
          setState(() => _customers = c);
        }),
        _db.getProducts(activeOnly: true).then((p) {
          if (!mounted) return;
          setState(() => _products = p.where((x) => x.trackVariants).toList());
        }),
        _db.expireDueLaybys(staffName: _staffName, staffId: _staffId),
        _db.getLaybys().then((l) {
          if (!mounted) return;
          setState(() => _laybys = l);
        }),
      ]);
      if (!mounted) return;
      setState(() {
        _customer = _customers.isNotEmpty ? _customers.first : null;
        _product = _products.isNotEmpty ? _products.first : null;
        if (_product != null) {
          _loadVariants(_product!.id!);
        }
      });
    } catch (error) {
      if (mounted) {
        _message('$error');
      }
    }
  }

  Future<void> _loadVariants(int productId) async {
    final variants = await _db.getVariants(productId);
    if (!mounted) return;
    setState(() {
      _variants = variants;
      _variant = variants.isNotEmpty ? variants.first : null;
    });
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _create() async {
    final customer = _customer;
    final product = _product;
    final variant = _variant;
    final qty = double.tryParse(_qtyCtrl.text.trim());
    final depositMajor = double.tryParse(_depositCtrl.text.trim());
    final reference = _referenceCtrl.text.trim();
    final days = int.tryParse(_dueDaysCtrl.text.trim());

    if (customer == null ||
        product == null ||
        product.id == null ||
        variant == null ||
        variant.id == null ||
        qty == null ||
        qty <= 0 ||
        depositMajor == null ||
        depositMajor <= 0 ||
        days == null ||
        days <= 0) {
      _message(
          'Choose a customer, style and variant, then enter valid quantity, deposit and due days.');
      return;
    }

    final sellPrice = variant.sellPrice;
    final total = Money.fromMinor((sellPrice.minorUnits * qty).round());
    final deposit = Money.fromMajor(depositMajor);
    if (deposit.isZero || deposit.isNegative || deposit > total) {
      _message('Deposit must be positive and no greater than the total.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _db.createLayby(
        customerId: customer.id!,
        items: [
          SaleItem(
            saleId: 0,
            productId: product.id!,
            productName: product.name,
            variantId: variant.id,
            variantName: variant.label,
            qty: qty,
            unitPrice: sellPrice,
            unitCost: variant.costPrice,
          )
        ],
        deposit: deposit,
        depositMethod: _depositMethod,
        depositReference: reference.isEmpty ? null : reference,
        dueAt: DateTime.now().add(Duration(days: days)),
        staffName: _staffName,
        staffId: _staffId,
      );
      _qtyCtrl.text = '1';
      _depositCtrl.clear();
      _referenceCtrl.clear();
      _dueDaysCtrl.text = '30';
      await _load();
      _message('Lay-by created and variant stock reserved.');
    } catch (error) {
      _message('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pay(Layby layby) async {
    final amount = await _amountDialog('Record payment', layby.balance);
    if (amount == null) return;

    final method = await _paymentMethodDialog();
    if (method == null) return;

    final reference = await _referenceDialog();
    try {
      await _db.addLaybyPayment(
        laybyId: layby.id,
        amount: amount,
        method: method,
        reference: reference,
        staffName: _staffName,
        staffId: _staffId,
      );
      await _load();
    } catch (error) {
      _message('$error');
    }
  }

  Future<String?> _paymentMethodDialog() async {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).paymentMethod),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.money_outlined),
              title: Text(AppLocalizations.of(context).cash),
              onTap: () => Navigator.pop(ctx, 'cash'),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: Text(AppLocalizations.of(context).mPesa),
              onTap: () => Navigator.pop(ctx, 'mpesa'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: Text(AppLocalizations.of(context).bankTransfer),
              onTap: () => Navigator.pop(ctx, 'bank_transfer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _referenceDialog() async {
    final controller = TextEditingController();
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).paymentReferenceOptional),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Reference number'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(AppLocalizations.of(context).skip)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(AppLocalizations.of(context).save)),
        ],
      ),
    );
  }

  Future<Money?> _amountDialog(String title, Money maximum) async {
    final controller = TextEditingController();
    final value = await showDialog<Money>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: 'Amount (KES), max ${maximum.asMajor}'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context).cancel)),
          FilledButton(
              onPressed: () {
                final major = double.tryParse(controller.text.trim());
                if (major == null || major <= 0) return;
                Navigator.pop(context, Money.fromMajor(major));
              },
              child: Text(AppLocalizations.of(context).save)),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _complete(Layby layby) async {
    try {
      await _db.completeLayby(layby.id,
          staffName: _staffName, staffId: _staffId);
      await _load();
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _cancel(Layby layby) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).cancelLayBy2),
        content:
            Text('Refund ${layby.paid.asMajor} and release the reservation?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).keep)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).cancelLayBy)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.cancelLayby(
          laybyId: layby.id, staffName: _staffName, staffId: _staffId);
      await _load();
    } catch (error) {
      _message('$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final type = AppTypography.of(context);

    return RefreshIndicator(
      onRefresh: _load,
      child: AdaptivePage(
        scrollable: true,
        maxContentWidth: _laybyScreenMaxWidth,
        padding: PageGutter.of(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupReminderBanner(onBackupNow: () => performBackup(context)),
            SizedBox(height: spacing.section),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.reserveScreenTitle,
                        style: AppTypography.of(context).headlineSmall,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        l10n.reserveScreenSubtitle,
                        style: type.bodyMedium?.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.sm),
            // Creation form
            SurfaceCard(
              padding: EdgeInsets.all(spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    l10n.reserveNewReserve,
                    style:
                        type.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: spacing.sm),
                  DropdownButtonFormField<Customer>(
                    initialValue: _customer,
                    decoration: InputDecoration(
                      labelText: l10n.reserveCustomer,
                    ),
                    items: _customers
                        .map((c) => DropdownMenuItem<Customer>(
                              value: c,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _customer = v),
                  ),
                  SizedBox(height: spacing.sm),
                  DropdownButtonFormField<Product>(
                    initialValue: _product,
                    decoration: InputDecoration(
                      labelText: l10n.reserveStyle,
                    ),
                    items: _products
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.name),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _product = v;
                        _variant = null;
                        if (v != null) {
                          _loadVariants(v.id!);
                        }
                      });
                    },
                  ),
                  SizedBox(height: spacing.sm),
                  if (_variants.isNotEmpty)
                    DropdownButtonFormField<ProductVariant>(
                      initialValue: _variant,
                      decoration: InputDecoration(
                        labelText: l10n.reserveVariant,
                      ),
                      items: _variants
                          .map((v) => DropdownMenuItem(
                                value: v,
                                child: Text(
                                    '${v.label} · ${formatMoney(v.sellPrice)} · ${v.availableStockQty.toInt()} left'),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _variant = v),
                    ),
                  SizedBox(height: spacing.sm),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _qtyCtrl,
                          decoration: InputDecoration(
                            labelText: l10n.reserveQuantity,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                      SizedBox(width: spacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _depositCtrl,
                          decoration: InputDecoration(
                            labelText: l10n.reserveDeposit,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacing.sm),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _depositMethod,
                          decoration: InputDecoration(
                            labelText: l10n.reservePaymentMethod,
                          ),
                          items: <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                                value: 'cash', child: Text(AppLocalizations.of(context).cash)),
                            DropdownMenuItem(
                                value: 'mpesa', child: Text(AppLocalizations.of(context).mPesa)),
                            DropdownMenuItem(
                                value: 'bank_transfer',
                                child: Text(AppLocalizations.of(context).bankTransfer)),
                          ],
                          onChanged: (v) => setState(() => _depositMethod = v!),
                        ),
                      ),
                      SizedBox(width: spacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _referenceCtrl,
                          decoration: InputDecoration(
                            labelText: l10n.reserveReference,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacing.sm),
                  TextField(
                    controller: _dueDaysCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.reserveDueDays,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  SizedBox(height: spacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _create,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bookmark_add_outlined),
                      label: Text(_saving ? 'Saving…' : l10n.reserveCreate),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.xl),
            // Existing laybys
            Text(
              l10n.reserveReservations,
              style: type.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: spacing.sm),
            if (_laybys.isEmpty)
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(l10n.reserveNoReserves),
              )
            else
              ..._laybys.map(_laybyCard),
            SizedBox(height: spacing.section),
          ],
        ),
      ),
    );
  }

  Widget _laybyCard(Layby layby) {
    final AppSpacing spacing = AppSpacing.of(context);
    final AppColors colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final l10n = AppLocalizations.of(context);

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        layby.items
                            .map((item) => item.variantName.isNotEmpty
                                ? item.variantName
                                : item.productName)
                            .join(', '),
                        style: type.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: spacing.xs),
                      Chip(
                        label: Text(layby.status.wire),
                        backgroundColor: _statusColor(layby.status, colors),
                      ),
                    ],
                  ),
                ),
                Text(
                  'KSh ${layby.balance.asMajor.toStringAsFixed(0)}',
                  style: type.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: layby.balance.isZero
                        ? colors.success
                        : colors.onSurface,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.xs),
            Text(
              '${l10n.reserveCustomer} #${layby.customerId} · ${l10n.reserveDue} ${layby.dueAt.substring(0, 10)}',
              style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
            ),
            SizedBox(height: spacing.xs),
            Text(
              '${l10n.reservePaid} ${layby.paid.asMajor} / ${layby.total.asMajor}',
              style: type.labelSmall?.copyWith(color: colors.onSurfaceMuted),
            ),
            if (layby.isOpen) ...<Widget>[
              SizedBox(height: spacing.sm),
              Wrap(spacing: 8, children: [
                TextButton.icon(
                  onPressed: () => _pay(layby),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(AppLocalizations.of(context).payment),
                ),
                if (layby.balance.isZero)
                  TextButton.icon(
                    onPressed: () => _complete(layby),
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(AppLocalizations.of(context).complete),
                  ),
                TextButton.icon(
                  onPressed: () => _cancel(layby),
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(AppLocalizations.of(context).cancel),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Color? _statusColor(LaybyStatus status, AppColors colors) {
    return switch (status) {
      LaybyStatus.open => colors.warning,
      LaybyStatus.completed => colors.success,
      LaybyStatus.cancelled => colors.danger,
      LaybyStatus.expired => colors.danger,
    };
  }
}
