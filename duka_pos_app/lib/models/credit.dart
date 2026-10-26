/// Customers, their credit accounts, and the append-only ledger behind them.
///
/// A customer is a name and a phone; a credit account is what the SHOP owes
/// against them. The two are kept apart because the money is not the person:
/// the balance lives only in [CreditLedgerEntry] rows (append-only — a
/// correction is a new row, never an edit), and [Customer.balanceMinor] is a
/// CACHE of that sum, maintained inside the same transaction as the row that
/// changes it rather than recomputed on read.
///
/// Money is integer minor units throughout (see utils/money.dart). A quantity
/// is signed: positive INCREASES what the customer owes.
library;

import '../utils/kenya_phone.dart' show phoneDisplayForm;
import '../utils/money.dart';

// Re-exported so a credit screen needs one import for both the models and the
// phone helpers they display with.
export '../utils/kenya_phone.dart' show normaliseKenyanPhone, phoneDisplayForm;


/// One customer of the shop.
class Customer {
  final int? id;

  /// For future sync. Created at the moment the row is written, unique from
  /// day one, so a synced copy can join its origin without a backfill.
  final String uuid;
  final String name;

  /// Canonical (+254…) form, or null. The locally typed form is a display
  /// concern (see [phoneDisplayForm]) and is never stored.
  final String? phone;

  /// The customer's KRA PIN, for business customers. Sent on the eTIMS
  /// invoice when present; never shown on a receipt for a person.
  final String? tin;
  final String? notes;

  /// What this customer may owe, in minor units. Null means "use the shop's
  /// default limit"; a figure here overrides it for this customer alone.
  final int? creditLimitMinor;

  /// What the customer owes right now. Cached, and never read for anything
  /// the ledger itself could answer — see [Customer.creditEntriesSum].
  final int balanceMinor;
  final bool active;
  final String createdAt;

  Customer({
    this.id,
    required this.uuid,
    required this.name,
    this.phone,
    this.tin,
    this.notes,
    this.creditLimitMinor,
    this.balanceMinor = 0,
    this.active = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'uuid': uuid,
        'name': name,
        'phone': phone,
        'tin': tin,
        'notes': notes,
        'credit_limit_minor': creditLimitMinor,
        'balance_minor': balanceMinor,
        'active': active ? 1 : 0,
        'created_at': createdAt,
      };

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        id: m['id'],
        uuid: m['uuid'] as String,
        name: m['name'] as String,
        phone: m['phone'] as String?,
        tin: m['tin'] as String?,
        notes: m['notes'] as String?,
        creditLimitMinor: (m['credit_limit_minor'] as num?)?.toInt(),
        balanceMinor: (m['balance_minor'] as num?)?.toInt() ?? 0,
        active: (m['active'] as num?)?.toInt() == 1,
        createdAt: m['created_at'] as String,
      );

  /// The phone as the shop typed it: 07xx/01xx for +254 numbers, otherwise
  /// the canonical form. Returns null when there is no phone with digits —
  /// an empty field is not a number to format.
  String? get phoneDisplay =>
      phone == null || phone!.isEmpty ? null : phoneDisplayForm(phone!);

  /// What this customer may owe: their own override, or [shopDefaultLimit].
  int effectiveLimit(int shopDefaultLimit) =>
      creditLimitMinor ?? shopDefaultLimit;

  /// What is left before this customer reaches [limit]. Negative when they are
  /// already past it (a write-off or an approved over-limit sale can do that).
  Money headroomUnder(int limit) =>
      Money.fromMinor(limit - balanceMinor);

  bool get owes => balanceMinor > 0;
}

/// What a ledger entry is.
enum CreditEntryType {
  /// A credit sale. Positive.
  charge('charge'),

  /// Money the customer paid back. Negative.
  payment('payment'),

  /// A signed correction by a manager (with an approver when the manager is a
  /// cashier-less role). Positive or negative.
  adjustment('adjustment'),

  /// Debt given up on. Negative; surfaces as a Bad-debts expense.
  writeoff('writeoff'),

  /// A returned credit sale. Negative.
  returnCredit('return_credit');

  const CreditEntryType(this.wire);
  final String wire;

  static CreditEntryType fromWire(String value) =>
      values.firstWhere((t) => t.wire == value,
          orElse: () => CreditEntryType.charge);
}

/// One append-only row of the credit ledger.
class CreditLedgerEntry {
  final int? id;
  final String uuid;
  final int customerId;

  /// [CreditEntryType], deciding the sign convention of [amountMinor].
  final CreditEntryType entryType;

  /// Positive increases what the customer owes; negative reduces it.
  final int amountMinor;

  final int? saleId;
  final int? returnId;

  /// For a payment: `cash` or `mpesa`. Null for every other entry type.
  final String? paymentMethod;

  /// An M-Pesa code or a typed reference.
  final String? reference;

  /// The shift a CASH payment was taken in — the drawer it added to.
  final int? shiftId;

  final int? staffId;
  final String staffName;

  /// The manager or owner who approved the entry, when it needed one
  /// (adjustments, write-offs, over-limit sales).
  final int? approvedBy;
  final String? note;
  final String createdAt;

  CreditLedgerEntry({
    this.id,
    required this.uuid,
    required this.customerId,
    required this.entryType,
    required this.amountMinor,
    this.saleId,
    this.returnId,
    this.paymentMethod,
    this.reference,
    this.shiftId,
    this.staffId,
    required this.staffName,
    this.approvedBy,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'uuid': uuid,
        'customer_id': customerId,
        'entry_type': entryType.wire,
        'amount_minor': amountMinor,
        'sale_id': saleId,
        'return_id': returnId,
        'payment_method': paymentMethod,
        'reference': reference,
        'shift_id': shiftId,
        'staff_id': staffId,
        'staff_name': staffName,
        'approved_by': approvedBy,
        'note': note,
        'created_at': createdAt,
      };

  factory CreditLedgerEntry.fromMap(Map<String, dynamic> m) =>
      CreditLedgerEntry(
        id: m['id'],
        uuid: m['uuid'] as String,
        customerId: m['customer_id'] as int,
        entryType: CreditEntryType.fromWire(m['entry_type'] as String),
        amountMinor: (m['amount_minor'] as num?)?.toInt() ?? 0,
        saleId: (m['sale_id'] as num?)?.toInt(),
        returnId: (m['return_id'] as num?)?.toInt(),
        paymentMethod: m['payment_method'] as String?,
        reference: m['reference'] as String?,
        shiftId: (m['shift_id'] as num?)?.toInt(),
        staffId: (m['staff_id'] as num?)?.toInt(),
        staffName: (m['staff_name'] as String?) ?? '',
        approvedBy: (m['approved_by'] as num?)?.toInt(),
        note: m['note'] as String?,
        createdAt: m['created_at'] as String? ?? '',
      );
}

/// One link between a payment and a charge it settles, for aging.
class CreditAllocation {
  final int paymentEntryId;
  final int chargeEntryId;
  final int amountMinor;

  const CreditAllocation({
    required this.paymentEntryId,
    required this.chargeEntryId,
    required this.amountMinor,
  });

  Map<String, dynamic> toMap() => {
        'payment_entry_id': paymentEntryId,
        'charge_entry_id': chargeEntryId,
        'amount_minor': amountMinor,
      };
}

/// The aging buckets a debt falls into, by the age of its OLDEST unpaid
/// charge. Days 0-7, 8-30, 31-60, over 60 — the boundaries the spec fixes.
enum DebtAgeBucket {
  upTo7Days(0),
  upTo30Days(8),
  upTo60Days(31),
  over60Days(61);

  const DebtAgeBucket(this.firstDay);

  /// The first day a debt lives in this bucket.
  final int firstDay;

  static DebtAgeBucket forAge(int days) {
    if (days <= 7) return DebtAgeBucket.upTo7Days;
    if (days <= 30) return DebtAgeBucket.upTo30Days;
    if (days <= 60) return DebtAgeBucket.upTo60Days;
    return DebtAgeBucket.over60Days;
  }
}

/// Spreads [availableMinor] of payment money across [chargeIds] oldest first,
/// giving each charge up to its own outstanding amount.
///
/// The invariant the tests hold: the allocations it returns NEVER exceed
/// [availableMinor] in total, and no charge is allocated more than
/// [remainingOnCharge]. Charges are given in age order — oldest first.
List<CreditAllocation> allocateOldestFirst({
  required List<({int entryId, int outstandingMinor})> charges,
  required int availableMinor,
  required int paymentEntryId,
  int alreadyAllocated = 0,
}) {
  var remaining = availableMinor - alreadyAllocated;
  final out = <CreditAllocation>[];
  for (final charge in charges) {
    if (remaining <= 0) break;
    final applied = remaining < charge.outstandingMinor
        ? remaining
        : charge.outstandingMinor;
    if (applied <= 0) continue;
    out.add(CreditAllocation(
      paymentEntryId: paymentEntryId,
      chargeEntryId: charge.entryId,
      amountMinor: applied,
    ));
    remaining -= applied;
  }
  return out;
}

/// The default template a reminder message is built from, before the shop
/// overrides it. Placeholders are {shop}, {name}, {balance} and {till}.
const String kDefaultReminderTemplate =
    'Hello {name}, this is {shop}. Your balance is {balance}. '
    'Kindly pay at the till. Thank you.';

/// Fills the reminder template.
String buildReminderMessage({
  required String template,
  required String shopName,
  required String customerName,
  required Money balance,
  String? untilText,
}) {
  return template
      .replaceAll('{shop}', shopName)
      .replaceAll('{name}', customerName)
      .replaceAll('{balance}', formatMoney(balance))
      .replaceAll('{till}', untilText ?? '');
}
