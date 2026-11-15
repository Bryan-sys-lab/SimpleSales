import 'package:duka_pos/profile/shop_profile.dart';
import 'package:duka_pos/services/cross_shop_activity.dart';
import 'package:duka_pos/services/cross_shop_activity_reader.dart';
import 'package:duka_pos/ui/dialogs/verify_before_create.dart';
import 'package:duka_pos/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

CrossShopActivity _event({
  required String id,
  required String tenant,
  required DateTime at,
  int minor = 10000,
  bool remote = false,
  String type = 'sale',
}) =>
    CrossShopActivity(
      eventId: id,
      sourceId: id,
      sourceType: type,
      tenantId: tenant,
      shopName: 'Amina Duka',
      businessProfile: ShopProfile.duka,
      createdAt: at,
      type: type,
      status: 'completed',
      amount: Money.fromMinor(minor),
      workspaceKey: tenant,
      isRemote: remote,
    );

void main() {
  group('withoutDuplicates', () {
    final at = DateTime(2026, 10, 25, 10, 0, 5);

    test('a synced sale is shown once, from the device', () {
      final events = <CrossShopActivity>[
        _event(id: 'local-sale:ws:7', tenant: 't1', at: at),
        _event(id: 'srv-91', tenant: 't1', at: at, remote: true),
      ];
      final kept = CrossShopActivityReader.withoutDuplicates(events);
      expect(kept.map((e) => e.eventId), <String>['local-sale:ws:7']);
    });

    test('a sale only the backend has is kept', () {
      final events = <CrossShopActivity>[
        _event(id: 'local-sale:ws:7', tenant: 't1', at: at),
        _event(
            id: 'srv-92',
            tenant: 't1',
            at: at.add(const Duration(minutes: 3)),
            remote: true),
      ];
      expect(CrossShopActivityReader.withoutDuplicates(events), hasLength(2));
    });

    test('the same time and amount in ANOTHER shop is not a duplicate', () {
      final events = <CrossShopActivity>[
        _event(id: 'local-sale:ws:7', tenant: 't1', at: at),
        _event(id: 'srv-93', tenant: 't2', at: at, remote: true),
      ];
      expect(CrossShopActivityReader.withoutDuplicates(events), hasLength(2));
    });
  });

  test('same-second events order by id, the same way the cursor reads them',
      () {
    final at = DateTime(2026, 10, 25, 10, 0, 5);
    final events = <CrossShopActivity>[
      _event(id: 'a', tenant: 't', at: at),
      _event(id: 'c', tenant: 't', at: at),
      _event(id: 'b', tenant: 't', at: at),
    ]..sort(CrossShopActivityReader.compareNewestFirst);
    expect(events.map((e) => e.eventId), <String>['c', 'b', 'a']);
  });

  test('a backend row is always marked remote', () {
    final event = _event(id: 'srv-1', tenant: 't', at: DateTime(2026, 10, 25));
    expect(event.isRemote, isFalse);
    expect(event.asRemote().isRemote, isTrue);
    expect(event.asRemote().eventId, 'srv-1');
  });

  group('VerificationGateResult', () {
    test('only an accepted code lets a shop be created', () {
      const cancelled = VerificationGateResult.cancelled();
      expect(cancelled.isAccepted, isFalse);
      expect(cancelled.isFailed, isFalse);

      const failed = VerificationGateResult.failed('No connection');
      expect(failed.isAccepted, isFalse);
      expect(failed.isFailed, isTrue);
      expect(failed.message, 'No connection');
    });
  });
}
