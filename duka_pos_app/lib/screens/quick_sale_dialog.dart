import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../data/local/repositories/sales_repository.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../models/credit.dart';
import '../utils/money.dart';
import '../profile/shop_profile.dart';
import '../services/app_state.dart';
import '../services/roles.dart';
import '../services/receipt_actions_service.dart';
import '../ui/dialogs/manager_approval_sheet.dart';
import '../ui/components/success_view.dart';
import '../theme/app_spacing.dart';
import 'customer_credit_sheets.dart';

/// Money-first sale for the Open profile. It remains a normal sale ledger row
/// so transactions, analytics, backup, and sync all see it.
Future<int?> showOpenQuickSaleDialog({required BuildContext context}) =>
    showQuickSaleDialog(context: context, profile: ShopProfile.open);

/// Shared QuickSale entry point. Opens a modal dialog in place; never pushes a
/// route. Returns the committed sale id, or null when cancelled/failed.
Future<int?> showQuickSaleDialog({
  required BuildContext context,
  required ShopProfile profile,
}) async {
  final appState = context.read<AppState>();
  final db = DatabaseHelper.instance;
  final products = await db.getProducts();
  final pools = await db.getCostPools();
  final bool creditEnabled = await db.getCreditEnabled();
  final bool creditRoleAllowed = appState.isOwnerSession ||
      (appState.hasPermission(PermissionKey.sellOnCredit) &&
          await db.getCreditCashiersAllowed());
  if (!context.mounted) return null;

  final qtyController = TextEditingController(text: '1');
  final amountController = TextEditingController();
  final itemNameController = TextEditingController();
  final customers = await db.getCustomers(activeOnly: true);
  if (!context.mounted) return null;
  final referenceController = TextEditingController();
  Product? selectedProduct;
  Customer? selectedCustomer;
  int? selectedPoolId;
  String method = 'cash';

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('QuickSale'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (pools.isNotEmpty)
                DropdownButtonFormField<int?>(
                  initialValue: selectedPoolId,
                  decoration: const InputDecoration(
                      labelText: 'Cost of Goods pool (optional)'),
                  items: <DropdownMenuItem<int?>>[
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('No pool allocation')),
                    for (final pool in pools)
                      DropdownMenuItem<int?>(
                        value: pool['id'] as int,
                        child: Text(pool['name'] as String? ?? 'Cost pool'),
                      ),
                  ],
                  onChanged: (value) => setState(() => selectedPoolId = value),
                ),
              SizedBox(height: AppSpacing.of(ctx).md),
              DropdownButtonFormField<Product>(
                initialValue: selectedProduct,
                decoration:
                    const InputDecoration(labelText: 'Product (optional)'),
                items: <DropdownMenuItem<Product>>[
                  for (final p in products)
                    DropdownMenuItem<Product>(value: p, child: Text(p.name)),
                ],
                onChanged: (v) {
                  setState(() {
                    selectedProduct = v;
                  });
                },
              ),
              SizedBox(height: AppSpacing.of(ctx).md),
              if (selectedProduct == null)
                TextField(
                  controller: itemNameController,
                  decoration: const InputDecoration(
                    labelText: 'Item name',
                    helperText: 'Name of the item being sold',
                  ),
                ),
              if (selectedProduct == null)
                SizedBox(height: AppSpacing.of(ctx).md),
              TextField(
                controller: qtyController,
                decoration: const InputDecoration(labelText: 'Quantity'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              SizedBox(height: AppSpacing.of(ctx).md),
              if (selectedProduct != null)
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Configured unit price',
                  ),
                  child: Text(formatMoney(selectedProduct!.sellPrice)),
                ),
              if (selectedProduct != null)
                SizedBox(height: AppSpacing.of(ctx).md),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount (KES)',
                  helperText:
                      'Leave blank to use the selected product price × quantity',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: InputDecoration(
                  labelText: 'Payment method',
                  helperText: !creditEnabled
                      ? 'Customer credit is disabled in Settings'
                      : !creditRoleAllowed
                          ? 'You do not have permission to record credit sales'
                          : null,
                ),
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem(value: 'cash', child: Text('cash')),
                  const DropdownMenuItem(value: 'mpesa', child: Text('mpesa')),
                  const DropdownMenuItem(
                    value: 'bank_transfer',
                    child: Text('bank transfer'),
                  ),
                  DropdownMenuItem(
                    value: 'credit',
                    enabled: creditEnabled && creditRoleAllowed,
                    child: const Text('Customer credit / tab'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => method = v);
                },
              ),
              if (method == 'credit')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    DropdownButtonFormField<Customer>(
                      initialValue: selectedCustomer?.id == null
                          ? null
                          : selectedCustomer,
                      decoration: const InputDecoration(labelText: 'Customer'),
                      items: <DropdownMenuItem<Customer>>[
                        for (final customer in customers)
                          DropdownMenuItem<Customer>(
                              value: customer, child: Text(customer.name)),
                      ],
                      onChanged: (value) =>
                          setState(() => selectedCustomer = value),
                    ),
                    SizedBox(height: AppSpacing.of(ctx).sm),
                    ActionChip(
                      onPressed: () async {
                        final picked = await showCustomerPickerSheet(
                          ctx,
                          persistNewCustomer: false,
                        );
                        if (picked != null) {
                          setState(() => selectedCustomer = picked);
                        }
                      },
                      avatar: const Icon(Icons.person_add_alt_1, size: 18),
                      label: Text(selectedCustomer?.id == null
                          ? 'Choose or create customer'
                          : 'Change customer'),
                    ),
                  ],
                ),
              SizedBox(height: AppSpacing.of(ctx).md),
              TextField(
                  controller: referenceController,
                  decoration:
                      const InputDecoration(labelText: 'Reference (optional)')),
            ],
          ),
        ),
        actions: <Widget>[
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ActionChip(
                onPressed: () => Navigator.pop(ctx),
                label: Text(AppLocalizations.of(context).cancel),
              ),
              ActionChip(
                avatar: const Icon(Icons.point_of_sale, size: 18),
                onPressed: () => Navigator.pop(ctx, <String, dynamic>{
                  'qty': qtyController.text.trim(),
                  'amount': amountController.text.trim(),
                  'method': method,
                  'reference': referenceController.text.trim(),
                  'productId': selectedProduct?.id,
                  'itemName': itemNameController.text.trim(),
                  'customerId': selectedCustomer?.id,
                  'customer': selectedCustomer,
                  'poolId': selectedPoolId,
                }),
                label: Text(AppLocalizations.of(context).sell),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  if (result == null) return null;
  final qty = double.tryParse((result['qty'] ?? '').toString());
  final productId = result['productId'] as int?;
  final itemName = (result['itemName'] ?? '').toString().trim();
  final enteredAmount = parseMoneyInput((result['amount'] ?? '').toString());
  if (qty == null ||
      qty <= 0 ||
      (productId == null && (enteredAmount == null || enteredAmount <= 0))) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Choose a product or enter a valid amount and quantity')),
      );
    }
    return null;
  }
  final product =
      productId == null ? null : products.firstWhere((p) => p.id == productId);
  final unitPrice = product?.priceFor(SalePortion.full);
  if (product != null && unitPrice!.minorUnits <= 0 && enteredAmount == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The product has no configured price')),
      );
    }
    return null;
  }

  try {
    final method = (result['method'] ?? 'cash') as String;
    final customerId = result['customerId'] as int?;
    final customerDraft = result['customer'] as Customer?;
    final costPoolId = result['poolId'] as int?;
    int? creditApprovedBy;
    if (method == 'credit') {
      if (customerId == null && customerDraft == null) {
        throw StateError('Select a customer before recording on credit');
      }
      if (!await db.getCreditEnabled()) {
        throw StateError('Customer credit is disabled in Settings');
      }
      if (!appState.isOwnerSession &&
          (!appState.hasPermission(PermissionKey.sellOnCredit) ||
              !await db.getCreditCashiersAllowed())) {
        throw StateError('You do not have permission to record credit sales');
      }
      final customer = customerId == null
          ? customerDraft
          : await db.getCustomerById(customerId);
      if (customer == null || !customer.active) {
        throw StateError('That customer is not active');
      }
      final chargeMinor =
          Money.fromMajor(enteredAmount ?? unitPrice!.times(qty).asMajor)
              .minorUnits;
      final limit = customer.effectiveLimit(await db.getCreditDefaultLimit());
      if (customer.balanceMinor + chargeMinor > limit &&
          await db.getCreditLimitMode() != 'warn') {
        if (!context.mounted) return null;
        final approver = await showManagerApprovalSheet(
          context,
          purpose:
              'This sale would take ${customer.name} past their credit limit',
        );
        if (approver == null) return null;
        creditApprovedBy = approver.id;
      }
    }
    if (product == null) {
      final saleId = await db.recordOpenQuickSale(
        amount: Money.fromMajor(enteredAmount!),
        paymentMethod: method,
        paymentReference: (result['reference'] ?? '').toString().isEmpty
            ? null
            : (result['reference'] ?? '').toString(),
        staffId: appState.currentStaffId,
        staffName: appState.currentStaffName ?? 'Owner',
        profile: profile,
        itemName: itemName.isEmpty ? null : itemName,
        customerId: method == 'credit' ? customerId : null,
        customerDraft: method == 'credit' ? customerDraft : null,
        creditApprovedBy: creditApprovedBy,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Quick sale recorded')));
      }
      return saleId;
    }
    final saleId = await SalesRepository.instance.recordSale(
      items: <SaleItem>[
        SaleItem(
          saleId: 0,
          productId: product.id!,
          productName: product.name,
          qty: qty,
          unitPrice: enteredAmount == null
              ? unitPrice!
              : Money.fromMajor(enteredAmount / qty),
          unitCost: product.costPrice,
          portion: 'full',
        ),
      ],
      enforceStock: product.trackStock,
      paymentMethod: method,
      paymentReference: (result['reference'] ?? '').toString().isEmpty
          ? null
          : (result['reference'] ?? '').toString(),
      staffId: appState.currentStaffId,
      staffName: appState.currentStaffName ?? 'Owner',
      customerId: method == 'credit' ? customerId : null,
      customerDraft: method == 'credit' ? customerDraft : null,
      creditApprovedBy: creditApprovedBy,
      costPoolId: costPoolId,
    );
    if (context.mounted) {
      final committed = await db.getSaleById(saleId);
      if (!context.mounted || committed == null) return saleId;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SuccessView(
            title: 'Sale recorded',
            message: committed.paymentMethod,
            amountLabel: formatMoney(committed.total),
            facts: <SuccessFact>[
              SuccessFact(
                label: 'Paid',
                value: formatMoney(committed.amountTendered),
              ),
              SuccessFact(
                label: 'Change',
                value: formatMoney(committed.changeGiven),
              ),
            ],
            onNext: () => Navigator.pop(sheetContext),
            nextLabel: 'Done',
            secondaryAction: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () => ReceiptActionsService.instance
                      .shareTextReceipt(context, saleId),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share receipt'),
                ),
                OutlinedButton.icon(
                  onPressed: () => ReceiptActionsService.instance
                      .sharePdfReceipt(context, saleId),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Share PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: () => ReceiptActionsService.instance
                      .printReceipt(context, saleId),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print receipt'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return saleId;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    return null;
  }
}
