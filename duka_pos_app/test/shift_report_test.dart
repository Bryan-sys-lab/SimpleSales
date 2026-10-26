import 'dart:convert';

import 'package:duka_pos/screens/reports_shifts.dart';
import 'package:duka_pos/services/printer/receipt_builder.dart';
import 'package:duka_pos/services/printer/shift_report_builder.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final row = <String, dynamic>{
    'shift_id': 4,
    'report_number': 12,
    'created_at': '2026-10-25T10:00:00.000Z',
    'snapshot_json': jsonEncode({
      'shift_id': 4,
      'report_number': 12,
      'ended_at': '2026-10-25T10:00:00.000Z',
      'sale_count': 3,
      'gross_minor': 15000,
      'profit_minor': 4000,
      'expected_cash_minor': 10000,
      'counted_cash_minor': 9900,
      'variance_minor': -100,
      'vat_minor': 2069,
      'taxable_minor': 12931,
      'etims_issued': 0,
      'etims_pending': 3,
      'etims_rejected': 0,
      'kra_activated': false,
      'payment_mix': {
        'cash': {'count': 2, 'total_minor': 10000},
        'mpesa': {'count': 1, 'total_minor': 5000},
      },
    }),
  };

  test('Z snapshot preserves local tax and inactive-KRA comparison state', () {
    final report = ShiftReportSnapshot.fromRow(row);
    expect(report.reportNumber, 12);
    expect(report.vat, Money.fromMinor(2069));
    expect(report.taxable, Money.fromMinor(12931));
    expect(report.etimsPending, 3);
    expect(report.kraActivated, isFalse);
    expect(report.paymentMix['cash'], 10000);
  });

  test('Z report layout stays within both supported paper widths', () {
    final report = ShiftReportSnapshot.fromRow(row);
    final lines = buildShiftReportLines(report);
    for (final line in lines) {
      expect(line.render(k58mmColumnBudget).length,
          lessThanOrEqualTo(k58mmColumnBudget));
      expect(line.render(k80mmColumnBudget).length,
          lessThanOrEqualTo(k80mmColumnBudget));
    }
  });
}
