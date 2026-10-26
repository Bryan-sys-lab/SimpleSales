import 'package:flutter_test/flutter_test.dart';

import 'package:duka_pos/services/owner_business_sync_service.dart';

void main() {
  test('owner sync has an explicit business-data allowlist', () {
    final domains = OwnerBusinessSyncService.ownerBusinessDomains;

    expect(
        domains,
        containsAll(<String>[
          'catalogue',
          'staff',
          'sales',
          'customer_credit',
          'expenses_and_till_movements',
          'encrypted_full_backup',
        ]));
    expect(domains.toSet().length, domains.length);
    expect(
      domains.where((domain) => domain.contains('commercial')),
      isEmpty,
      reason: 'commercial intelligence must not enter owner business sync',
    );
  });
}
