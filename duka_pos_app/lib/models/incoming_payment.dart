import '../utils/money.dart';

class IncomingPayment {
  const IncomingPayment({
    required this.remoteId,
    required this.transactionId,
    required this.amount,
    required this.payerMasked,
    required this.receivedAt,
    required this.status,
    this.claimedAt,
    this.claimedBy,
  });

  final String remoteId;
  final String transactionId;
  final Money amount;
  final String payerMasked;
  final DateTime receivedAt;
  final String status;
  final DateTime? claimedAt;
  final String? claimedBy;

  factory IncomingPayment.fromMap(Map<String, dynamic> row) => IncomingPayment(
        remoteId: row['remote_id'] as String,
        transactionId: row['trans_id'] as String,
        amount: Money.fromMinor((row['amount_minor'] as num).toInt()),
        payerMasked: row['payer_masked'] as String? ?? '',
        receivedAt: DateTime.tryParse(row['received_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        status: row['status'] as String? ?? 'unclaimed',
        claimedAt: DateTime.tryParse(row['claimed_at'] as String? ?? ''),
        claimedBy: row['claimed_by'] as String?,
      );
}
