import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/models/tax_entity.dart';

void main() {
  test('parses the safe tax entity projection and consolidated turnover', () {
    final snapshot = TaxEntitySnapshot.fromResponse({
      'tax_entity': {
        'id': 'entity-1',
        'legal_form': 'company',
        'display_label': 'Example Limited',
        'kra_pin_set': true,
        'kra_pin_last4': '567X',
        'registered_tax_obligations': ['vat', 'etims'],
        'accounting_period_start_month': 7,
        'status': 'active',
        'rules': [
          {
            'id': 'rule-1',
            'tax_type': 'vat',
            'scope': 'standard-rated supplies',
            'jurisdiction': 'KE',
            'rate_basis_points': 1600,
            'tax_base': 'taxable_supply',
            'threshold_minor': null,
            'effective_from': '2026-10-25T00:00:00.000Z',
            'effective_to': null,
            'source_url': 'https://www.kra.go.ke/taxes/value-added-tax',
            'source_reference': 'KRA VAT guidance',
            'reviewed_at': '2026-10-25T00:00:00.000Z',
            'status': 'active',
          },
        ],
      },
      'mapping': {'outlet_reference': 'Nairobi-01'},
      'threshold': {
        'linked_shop_count': 3,
        'turnover_minor': 1250000,
        'status': 'calculated',
      },
      'vat_report': {
        'output_vat_minor': 1600,
        'lines_without_rule_snapshot': 0,
        'status': 'reconciled',
      },
    });

    expect(snapshot.id, 'entity-1');
    expect(snapshot.legalForm, 'company');
    expect(snapshot.kraPinLast4, '567X');
    expect(snapshot.obligations, ['vat', 'etims']);
    expect(snapshot.accountingPeriodStartMonth, 7);
    expect(snapshot.linkedShopCount, 3);
    expect(snapshot.turnover.minorUnits, 1250000);
    expect(snapshot.thresholdStatus, 'calculated');
    expect(snapshot.outletReference, 'Nairobi-01');
    expect(snapshot.rules, hasLength(1));
    expect(snapshot.rules.single.rateBasisPoints, 1600);
    expect(snapshot.rules.single.status, 'active');
    expect(snapshot.managedVatRatePercent, 16);
    expect(snapshot.vatReport!.outputVat.minorUnits, 1600);
    expect(snapshot.vatReport!.status, 'reconciled');
  });
}
