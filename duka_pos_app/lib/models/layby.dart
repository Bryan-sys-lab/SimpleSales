import '../utils/money.dart';

/// The durable state of a Fashion lay-by.
enum LaybyStatus {
  open('open'),
  completed('completed'),
  cancelled('cancelled'),
  expired('expired');

  const LaybyStatus(this.wire);
  final String wire;

  static LaybyStatus fromWire(String? value) => values.firstWhere(
        (status) => status.wire == value,
        orElse: () => LaybyStatus.open,
      );
}

class Layby {
  const Layby({
    required this.id,
    required this.uuid,
    required this.customerId,
    required this.status,
    required this.total,
    required this.paid,
    required this.dueAt,
    required this.createdAt,
    required this.staffName,
    this.staffId,
    this.saleId,
    this.completedAt,
    this.cancelledAt,
    this.items = const [],
    this.payments = const [],
  });

  final int id;
  final String uuid;
  final int customerId;
  final LaybyStatus status;
  final Money total;
  final Money paid;
  final String dueAt;
  final String createdAt;
  final String staffName;
  final int? staffId;
  final int? saleId;
  final String? completedAt;
  final String? cancelledAt;
  final List<LaybyItem> items;
  final List<LaybyPayment> payments;

  Money get balance => total - paid;
  bool get isOpen => status == LaybyStatus.open;

  factory Layby.fromMap(Map<String, dynamic> row,
      {List<LaybyItem> items = const [],
      List<LaybyPayment> payments = const []}) {
    return Layby(
      id: (row['id'] as num).toInt(),
      uuid: row['uuid'] as String,
      customerId: (row['customer_id'] as num).toInt(),
      status: LaybyStatus.fromWire(row['status'] as String?),
      total: Money.fromMinor((row['total_minor'] as num?)?.toInt() ?? 0),
      paid: Money.fromMinor((row['paid_minor'] as num?)?.toInt() ?? 0),
      dueAt: row['due_at'] as String,
      createdAt: row['created_at'] as String,
      staffName: row['staff_name'] as String,
      staffId: (row['staff_id'] as num?)?.toInt(),
      saleId: (row['sale_id'] as num?)?.toInt(),
      completedAt: row['completed_at'] as String?,
      cancelledAt: row['cancelled_at'] as String?,
      items: items,
      payments: payments,
    );
  }
}

class LaybyItem {
  const LaybyItem({
    required this.id,
    required this.laybyId,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.unitPrice,
    required this.unitCost,
    required this.total,
    this.variantId,
    this.variantName = '',
    this.discount = Money.zero,
  });

  final int id;
  final int laybyId;
  final int productId;
  final int? variantId;
  final String productName;
  final String variantName;
  final double qty;
  final Money unitPrice;
  final Money unitCost;
  final Money discount;
  final Money total;

  factory LaybyItem.fromMap(Map<String, dynamic> row) => LaybyItem(
        id: (row['id'] as num).toInt(),
        laybyId: (row['layby_id'] as num).toInt(),
        productId: (row['product_id'] as num).toInt(),
        variantId: (row['variant_id'] as num?)?.toInt(),
        productName: row['product_name'] as String,
        variantName: row['variant_name'] as String? ?? '',
        qty: (row['qty'] as num).toDouble(),
        unitPrice: Money.fromMinor((row['unit_price_minor'] as num).toInt()),
        unitCost: Money.fromMinor((row['unit_cost_minor'] as num).toInt()),
        discount:
            Money.fromMinor((row['discount_minor'] as num?)?.toInt() ?? 0),
        total: Money.fromMinor((row['total_minor'] as num).toInt()),
      );
}

class LaybyPayment {
  const LaybyPayment({
    required this.id,
    required this.laybyId,
    required this.method,
    required this.amount,
    required this.createdAt,
    required this.staffName,
    this.direction = 'in',
    this.reference,
    this.staffId,
  });

  final int id;
  final int laybyId;
  final String method;
  final Money amount;
  final String? reference;
  final String createdAt;
  final String staffName;
  final String direction;
  final int? staffId;

  factory LaybyPayment.fromMap(Map<String, dynamic> row) => LaybyPayment(
        id: (row['id'] as num).toInt(),
        laybyId: (row['layby_id'] as num).toInt(),
        method: row['method'] as String,
        amount: Money.fromMinor((row['amount_minor'] as num).toInt()),
        reference: row['reference'] as String?,
        createdAt: row['created_at'] as String,
        staffName: row['staff_name'] as String,
        direction: row['direction'] as String? ?? 'in',
        staffId: (row['staff_id'] as num?)?.toInt(),
      );

  bool get isRefund => direction == 'out';
}
