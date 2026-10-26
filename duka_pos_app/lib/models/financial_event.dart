/// One append-only financial fact emitted by a shared transaction writer.
///
/// Monetary amounts are signed minor-unit deltas, including reversals and
/// refunds. [inventoryDeltaMilliunits] is a signed quantity delta at 1/1000
/// of a unit. The event is deliberately normalized so every profile can use
/// the same reporting contract.
class FinancialEvent {
  const FinancialEvent({
    this.id,
    required this.uuid,
    required this.eventType,
    required this.sourceType,
    this.sourceId,
    required this.occurredAtUtc,
    this.revenueMinor = 0,
    this.cashInMinor = 0,
    this.cashOutMinor = 0,
    this.cogsMinor = 0,
    this.operatingExpenseMinor = 0,
    this.taxCollectedMinor = 0,
    this.receivableDeltaMinor = 0,
    this.payableDeltaMinor = 0,
    this.customerDepositDeltaMinor = 0,
    this.inventoryDeltaMilliunits = 0,
    this.metadataJson = '{}',
    this.previousHash,
    required this.integrityHash,
  });

  final int? id;
  final String uuid;
  final String eventType;
  final String sourceType;
  final int? sourceId;
  final String occurredAtUtc;
  final int revenueMinor;
  final int cashInMinor;
  final int cashOutMinor;
  final int cogsMinor;
  final int operatingExpenseMinor;
  final int taxCollectedMinor;
  final int receivableDeltaMinor;
  final int payableDeltaMinor;
  final int customerDepositDeltaMinor;
  final int inventoryDeltaMilliunits;
  final String metadataJson;
  final String? previousHash;
  final String integrityHash;

  factory FinancialEvent.fromMap(Map<String, dynamic> map) {
    return FinancialEvent(
      id: (map['id'] as num?)?.toInt(),
      uuid: map['uuid'] as String,
      eventType: map['event_type'] as String,
      sourceType: map['source_type'] as String,
      sourceId: (map['source_id'] as num?)?.toInt(),
      occurredAtUtc: map['occurred_at_utc'] as String,
      revenueMinor: (map['revenue_minor'] as num?)?.toInt() ?? 0,
      cashInMinor: (map['cash_in_minor'] as num?)?.toInt() ?? 0,
      cashOutMinor: (map['cash_out_minor'] as num?)?.toInt() ?? 0,
      cogsMinor: (map['cogs_minor'] as num?)?.toInt() ?? 0,
      operatingExpenseMinor:
          (map['operating_expense_minor'] as num?)?.toInt() ?? 0,
      taxCollectedMinor: (map['tax_collected_minor'] as num?)?.toInt() ?? 0,
      receivableDeltaMinor:
          (map['receivable_delta_minor'] as num?)?.toInt() ?? 0,
      payableDeltaMinor: (map['payable_delta_minor'] as num?)?.toInt() ?? 0,
      customerDepositDeltaMinor:
          (map['customer_deposit_delta_minor'] as num?)?.toInt() ?? 0,
      inventoryDeltaMilliunits:
          (map['inventory_delta_milliunits'] as num?)?.toInt() ?? 0,
      metadataJson: map['metadata_json'] as String? ?? '{}',
      previousHash: map['previous_hash'] as String?,
      integrityHash: map['integrity_hash'] as String,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'uuid': uuid,
        'event_type': eventType,
        'source_type': sourceType,
        'source_id': sourceId,
        'occurred_at_utc': occurredAtUtc,
        'revenue_minor': revenueMinor,
        'cash_in_minor': cashInMinor,
        'cash_out_minor': cashOutMinor,
        'cogs_minor': cogsMinor,
        'operating_expense_minor': operatingExpenseMinor,
        'tax_collected_minor': taxCollectedMinor,
        'receivable_delta_minor': receivableDeltaMinor,
        'payable_delta_minor': payableDeltaMinor,
        'customer_deposit_delta_minor': customerDepositDeltaMinor,
        'inventory_delta_milliunits': inventoryDeltaMilliunits,
        'metadata_json': metadataJson,
        'previous_hash': previousHash,
        'integrity_hash': integrityHash,
      };
}

/// The event names and source tables accepted by the shared transaction
/// engine. Keeping this registry beside the model prevents a new writer from
/// silently inventing an unreportable event type.
class FinancialEventContract {
  const FinancialEventContract._();

  static const Map<String, FinancialEventSemantics> semanticsByEventType =
      <String, FinancialEventSemantics>{
    'sale': FinancialEventSemantics(
        sourceTypes: <String>{'sale'},
        revenue: true,
        directCost: true,
        tax: true,
        cash: true,
        receivable: true,
        inventory: true),
    'expense': FinancialEventSemantics(
        sourceTypes: <String>{'expense'},
        cash: true,
        payable: true,
        operatingExpense: true),
    'expense_void': FinancialEventSemantics(
        sourceTypes: <String>{'expense'},
        cash: true,
        payable: true,
        operatingExpense: true),
    'expense_payment': FinancialEventSemantics(
        sourceTypes: <String>{'expense_payment'}, cash: true, payable: true),
    'purchase': FinancialEventSemantics(
        sourceTypes: <String>{'stock_receipt'}, payable: true, inventory: true),
    'purchase_void': FinancialEventSemantics(
        sourceTypes: <String>{'stock_receipt'}, payable: true, inventory: true),
    'refund': FinancialEventSemantics(
        sourceTypes: <String>{'sale_return'},
        revenue: true,
        directCost: true,
        tax: true,
        cash: true,
        receivable: true,
        operatingExpense: true,
        inventory: true),
    'credit_repayment': FinancialEventSemantics(
        sourceTypes: <String>{'credit_ledger'}, cash: true, receivable: true),
    'credit_adjustment': FinancialEventSemantics(
        sourceTypes: <String>{'credit_ledger'}, receivable: true),
    'credit_writeoff': FinancialEventSemantics(
        sourceTypes: <String>{'credit_ledger'}, receivable: true),
    'bad_debt_expense': FinancialEventSemantics(
        sourceTypes: <String>{'expense'}, operatingExpense: true),
    'stock_adjustment': FinancialEventSemantics(
        sourceTypes: <String>{'stock_adjustment'}, inventory: true),
    'stock_writeoff': FinancialEventSemantics(
        sourceTypes: <String>{'stock_writeoff'}, inventory: true),
    'stock_count': FinancialEventSemantics(
        sourceTypes: <String>{'stock_count'}, inventory: true),
    'stock_repack': FinancialEventSemantics(
        sourceTypes: <String>{'stock_repack'}, inventory: true),
    'layby_deposit': FinancialEventSemantics(
        sourceTypes: <String>{'layby'}, cash: true, deposit: true),
    'layby_payment': FinancialEventSemantics(
        sourceTypes: <String>{'layby'}, cash: true, deposit: true),
    'layby_complete':
        FinancialEventSemantics(sourceTypes: <String>{'layby'}, deposit: true),
    'layby_cancel': FinancialEventSemantics(
        sourceTypes: <String>{'layby'}, cash: true, deposit: true),
    'exchange_difference':
        FinancialEventSemantics(sourceTypes: <String>{'exchange'}, cash: true),
    'cost_pool_entry': FinancialEventSemantics(
        sourceTypes: <String>{'cost_pool_entry'}, cash: true, payable: true),
    'cost_pool_allocation': FinancialEventSemantics(
        sourceTypes: <String>{'sale_pool_allocation'}, directCost: true),
    'job_cost': FinancialEventSemantics(
        sourceTypes: <String>{'job_cost'},
        directCost: true,
        cash: true,
        payable: true),
    'job_completion': FinancialEventSemantics(
        sourceTypes: <String>{'job'},
        revenue: true,
        receivable: true,
        deposit: true),
    'job_payment': FinancialEventSemantics(
        sourceTypes: <String>{'job_payment'},
        cash: true,
        receivable: true,
        deposit: true),
    'owner_transaction': FinancialEventSemantics(
        sourceTypes: <String>{'owner_transaction'}, cash: true),
    'till_movement': FinancialEventSemantics(
        sourceTypes: <String>{'till_movement'}, cash: true),
  };

  static Set<String> get eventTypes => semanticsByEventType.keys.toSet();

  static void validate({
    required String eventType,
    required String sourceType,
    required int? sourceId,
    required String occurredAtUtc,
    required int revenueMinor,
    required int cashInMinor,
    required int cashOutMinor,
    required int cogsMinor,
    required int operatingExpenseMinor,
    required int taxCollectedMinor,
    required int receivableDeltaMinor,
    required int payableDeltaMinor,
    required int customerDepositDeltaMinor,
    required int inventoryDeltaMilliunits,
  }) {
    final semantics = semanticsByEventType[eventType];
    if (semantics == null || !semantics.sourceTypes.contains(sourceType)) {
      throw StateError(
          'Unsupported financial event contract: $eventType/$sourceType');
    }
    if (sourceId == null) {
      throw StateError('Financial events require a source id');
    }
    final timestamp = DateTime.tryParse(occurredAtUtc);
    if (timestamp == null || !timestamp.isUtc) {
      throw StateError('Financial events require a UTC timestamp');
    }
    if (!semantics.revenue && revenueMinor != 0) {
      throw StateError('$eventType cannot change revenue');
    }
    if (!semantics.directCost && cogsMinor != 0) {
      throw StateError('$eventType cannot change direct cost');
    }
    if (!semantics.operatingExpense && operatingExpenseMinor != 0) {
      throw StateError('$eventType cannot change operating expense');
    }
    if (!semantics.tax && taxCollectedMinor != 0) {
      throw StateError('$eventType cannot change tax');
    }
    if (!semantics.cash && (cashInMinor != 0 || cashOutMinor != 0)) {
      throw StateError('$eventType cannot change cash');
    }
    if (!semantics.receivable && receivableDeltaMinor != 0) {
      throw StateError('$eventType cannot change receivables');
    }
    if (!semantics.payable && payableDeltaMinor != 0) {
      throw StateError('$eventType cannot change payables');
    }
    if (!semantics.deposit && customerDepositDeltaMinor != 0) {
      throw StateError('$eventType cannot change customer deposits');
    }
    if (!semantics.inventory && inventoryDeltaMilliunits != 0) {
      throw StateError('$eventType cannot change inventory');
    }
  }
}

class FinancialEventSemantics {
  const FinancialEventSemantics({
    required this.sourceTypes,
    this.revenue = false,
    this.directCost = false,
    this.operatingExpense = false,
    this.tax = false,
    this.cash = false,
    this.receivable = false,
    this.payable = false,
    this.deposit = false,
    this.inventory = false,
  });

  final Set<String> sourceTypes;
  final bool revenue;
  final bool directCost;
  final bool operatingExpense;
  final bool tax;
  final bool cash;
  final bool receivable;
  final bool payable;
  final bool deposit;
  final bool inventory;
}

/// Reconciled totals from the normalized financial-event stream.
///
/// All monetary values are signed minor-unit deltas. The derived figures are
/// intentionally calculated from the same event contract used by writers, so
/// a statement cannot silently invent a second set of accounting rules.
class FinancialEventTotals {
  const FinancialEventTotals({
    this.revenueMinor = 0,
    this.cashInMinor = 0,
    this.cashOutMinor = 0,
    this.cogsMinor = 0,
    this.operatingExpenseMinor = 0,
    this.taxCollectedMinor = 0,
    this.receivableDeltaMinor = 0,
    this.payableDeltaMinor = 0,
    this.customerDepositDeltaMinor = 0,
    this.inventoryDeltaMilliunits = 0,
  });

  final int revenueMinor;
  final int cashInMinor;
  final int cashOutMinor;
  final int cogsMinor;
  final int operatingExpenseMinor;
  final int taxCollectedMinor;
  final int receivableDeltaMinor;
  final int payableDeltaMinor;
  final int customerDepositDeltaMinor;
  final int inventoryDeltaMilliunits;

  int get grossProfitMinor => revenueMinor - cogsMinor;
  int get netProfitMinor => grossProfitMinor - operatingExpenseMinor;
  int get netCashFlowMinor => cashInMinor - cashOutMinor;

  FinancialEventTotals operator +(FinancialEvent event) {
    return FinancialEventTotals(
      revenueMinor: revenueMinor + event.revenueMinor,
      cashInMinor: cashInMinor + event.cashInMinor,
      cashOutMinor: cashOutMinor + event.cashOutMinor,
      cogsMinor: cogsMinor + event.cogsMinor,
      operatingExpenseMinor:
          operatingExpenseMinor + event.operatingExpenseMinor,
      taxCollectedMinor: taxCollectedMinor + event.taxCollectedMinor,
      receivableDeltaMinor: receivableDeltaMinor + event.receivableDeltaMinor,
      payableDeltaMinor: payableDeltaMinor + event.payableDeltaMinor,
      customerDepositDeltaMinor:
          customerDepositDeltaMinor + event.customerDepositDeltaMinor,
      inventoryDeltaMilliunits:
          inventoryDeltaMilliunits + event.inventoryDeltaMilliunits,
    );
  }
}

/// The reconciled management statement exposed to report consumers.
///
/// [openingCashMinor] is explicit because a local till may not know its true
/// historical opening balance. When it is omitted by a caller, the resulting
/// closing cash is a calculated movement position, not a claim about physical
/// cash held before the selected period.
class FinancialStatement {
  const FinancialStatement({
    required this.totals,
    required this.openingCashMinor,
    this.openingCashIsKnown = false,
  });

  final FinancialEventTotals totals;
  final int openingCashMinor;
  final bool openingCashIsKnown;

  int get closingCashMinor => openingCashMinor + totals.netCashFlowMinor;
  int get revenueMinor => totals.revenueMinor;
  int get directCostMinor => totals.cogsMinor;
  int get operatingExpenseMinor => totals.operatingExpenseMinor;
  int get grossProfitMinor => totals.grossProfitMinor;
  int get netProfitMinor => totals.netProfitMinor;
  int get cashInMinor => totals.cashInMinor;
  int get cashOutMinor => totals.cashOutMinor;
  int get receivableDeltaMinor => totals.receivableDeltaMinor;
  int get payableDeltaMinor => totals.payableDeltaMinor;
  int get customerDepositDeltaMinor => totals.customerDepositDeltaMinor;
  int get inventoryDeltaMilliunits => totals.inventoryDeltaMilliunits;
}
