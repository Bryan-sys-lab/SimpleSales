/// One row of the stock ledger.
///
/// Every change to a stock count is one of these: a sale, a return, a
/// delivery, a correction, a count. The rows are append-only — a correction
/// is a new row, never an edit — which is what makes the ledger checkable
/// and what lets a shop's stock be explained months later.
library;

/// Why a stock count moved.
///
/// A closed vocabulary, not free text: a ledger whose movement types drift
/// into "sale" and "Sale" and "SALE" is a ledger that cannot be queried.
enum StockMovementType {
  /// The count the shop had when the ledger began.
  opening('opening'),

  /// Goods left the shelf because they were sold.
  sale('sale'),

  /// Goods came back because the sale was reversed.
  saleReturn('sale_return'),

  /// Goods arrived on a delivery.
  receipt('receipt'),

  /// A delivery was undone.
  receiptVoid('receipt_void'),

  /// Somebody corrected the count by hand.
  adjustment('adjustment'),

  /// A physical count found a different number.
  count('count'),

  /// Goods were thrown away rather than sold.
  writeoff('writeoff'),

  /// Goods came in from a spreadsheet.
  import('import'),

  /// A correction to an earlier mistake.
  correction('correction');

  const StockMovementType(this.wire);

  /// The value stored in the database and sent over the wire.
  final String wire;

  /// The type named by [value], or null when the value is not one of ours.
  static StockMovementType? fromWire(String? value) {
    for (final StockMovementType type in StockMovementType.values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// One immutable row of the stock ledger.
class StockMovement {
  const StockMovement({
    this.id,
    required this.uuid,
    required this.createdAt,
    required this.productId,
    this.variantId,
    required this.type,
    required this.qtyDelta,
    this.unitCostMinor,
    this.referenceType,
    this.referenceId,
    this.batchId,
    this.staffId,
    this.staffName,
    this.note,
    required this.balanceAfter,
  });

  final int? id;

  /// The row's identity, stable across devices.
  final String uuid;

  final DateTime createdAt;

  final int productId;

  /// The variant this moved, when it moved one variant's count.
  final int? variantId;

  final StockMovementType type;

  /// Signed: negative for goods that left, positive for goods that arrived.
  final double qtyDelta;

  /// The cost basis, in minor units. Null when the movement has no cost.
  final int? unitCostMinor;

  /// What this movement belongs to: a sale, a return, a receipt, a count.
  final String? referenceType;

  /// The row in the referenced table.
  final int? referenceId;

  /// The batch this movement belongs to, once batches exist.
  final int? batchId;

  final int? staffId;

  /// A snapshot of the name at the time. The staff row's own name is erased
  /// when the person is removed; this one is sealed with the rest.
  final String? staffName;

  final String? note;

  /// The count after this movement.
  ///
  /// Cached so the ledger reads without being summed. A reader that wants the
  /// truth sums the movements; this column is a convenience, and the check
  /// compares the two.
  final double balanceAfter;

  /// Whether this movement is a source of truth for the count, or a note
  /// about one.
  bool get isPositive => qtyDelta >= 0;

  factory StockMovement.fromMap(Map<String, dynamic> map) => StockMovement(
        id: map['id'] as int?,
        uuid: map['uuid'] as String? ?? '',
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        productId: (map['product_id'] as num?)?.toInt() ?? 0,
        variantId: (map['variant_id'] as num?)?.toInt(),
        type: StockMovementType.fromWire(map['movement_type'] as String?) ??
            StockMovementType.adjustment,
        qtyDelta: (map['qty_delta'] as num?)?.toDouble() ?? 0,
        unitCostMinor: (map['unit_cost_minor'] as num?)?.toInt(),
        referenceType: map['reference_type'] as String?,
        referenceId: (map['reference_id'] as num?)?.toInt(),
        batchId: (map['batch_id'] as num?)?.toInt(),
        staffId: (map['staff_id'] as num?)?.toInt(),
        staffName: map['staff_name'] as String?,
        note: map['note'] as String?,
        balanceAfter: (map['balance_after'] as num?)?.toDouble() ?? 0,
      );
}

/// How a payment was confirmed.
///
/// A payment that was taken but never matched to the till roll is money the
/// shop has and cannot prove — the same money, but a different fact about it.
enum SalePaymentStatus {
  /// The money is in and it is accounted for.
  confirmed('confirmed'),

  /// The money is in, but nobody has matched it to the till roll.
  unverified('unverified'),

  /// The money has not arrived yet.
  pending('pending');

  const SalePaymentStatus(this.wire);

  final String wire;

  static SalePaymentStatus? fromWire(String? value) {
    for (final SalePaymentStatus status in SalePaymentStatus.values) {
      if (status.wire == value) return status;
    }
    return null;
  }
}

/// One part of a sale's payment.
///
/// A sale can be paid in several parts — cash plus M-Pesa, M-Pesa plus on
/// account — and each part is one of these. The sum of the confirmed parts
/// is the sale's total; that is an invariant, and a test holds it.
class SalePayment {
  const SalePayment({
    this.id,
    required this.uuid,
    required this.saleId,
    required this.method,
    required this.amountMinor,
    this.tenderedMinor,
    this.changeMinor,
    this.reference,
    this.status = SalePaymentStatus.confirmed,
    this.pendingPaymentId,
    required this.createdAt,
  });

  final int? id;
  final String uuid;
  final int saleId;

  /// cash, mpesa, credit.
  final String method;

  /// What this part pays. Change is NOT included: change is not payment.
  final int amountMinor;

  /// What was handed over, cash only. Larger than [amountMinor] when there was
  /// change.
  final int? tenderedMinor;

  /// The change given back, cash only.
  final int? changeMinor;

  /// The M-Pesa transaction code, or a manual reference.
  final String? reference;

  final SalePaymentStatus status;

  /// The outstanding-payment row this part came from, when it came from one.
  final int? pendingPaymentId;

  final DateTime createdAt;

  /// Whether this part counts towards the sale's total.
  ///
  /// A pending payment has not arrived, so it is not part of what the sale
  /// collected — but it IS part of what was promised, and the reconciliation
  /// queue needs to see it.
  bool get countsTowardTotal => status != SalePaymentStatus.pending;

  factory SalePayment.fromMap(Map<String, dynamic> map) => SalePayment(
        id: map['id'] as int?,
        uuid: map['uuid'] as String? ?? '',
        saleId: (map['sale_id'] as num?)?.toInt() ?? 0,
        method: map['method'] as String? ?? 'cash',
        amountMinor: (map['amount_minor'] as num?)?.toInt() ?? 0,
        tenderedMinor: (map['tendered_minor'] as num?)?.toInt(),
        changeMinor: (map['change_minor'] as num?)?.toInt(),
        reference: map['reference'] as String?,
        status: SalePaymentStatus.fromWire(map['status'] as String?) ??
            SalePaymentStatus.confirmed,
        pendingPaymentId: (map['pending_payment_id'] as num?)?.toInt(),
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// A place where a count and its ledger disagree.
///
/// The Diagnostics screen's stock ledger check, and the shape a repair action
/// needs. A difference is never a rounding curiosity: it means one of the two
/// numbers is a lie, and the owner has to know which.
class LedgerDifference {
  const LedgerDifference({
    required this.productId,
    required this.productName,
    this.variantId,
    required this.counted,
    required this.ledger,
  });

  final int productId;
  final String productName;

  /// The variant the difference is about, when it is about one.
  final int? variantId;

  /// What the till says the product has.
  final double counted;

  /// What the ledger says it has.
  final double ledger;

  /// How far apart they are.
  double get difference => counted - ledger;

  @override
  String toString() => '$productName: counted $counted, ledger $ledger';
}
