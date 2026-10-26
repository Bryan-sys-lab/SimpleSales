import 'package:flutter_test/flutter_test.dart';
import 'package:duka_pos/services/cross_shop_activity.dart';

void main() {
  test('parses a normalized sale event without losing shop/profile/source', () {
    final page = CrossShopActivityPage.fromJson({
      'events': [
        {
          'eventId': 'sale:s1',
          'sourceId': 's1',
          'sourceType': 'sale',
          'tenantId': 'shop-1',
          'shopName': 'Fashion',
          'businessProfile': 'fashion',
          'createdAt': '2026-10-25T10:00:00.000Z',
          'type': 'sale',
          'status': 'completed',
          'amountMinor': 1250,
          'profitMinor': 400,
          'paymentMethod': 'mpesa',
          'actor': 'Amina',
        },
      ],
    });

    expect(page.events, hasLength(1));
    expect(page.events.single.shopName, 'Fashion');
    expect(page.events.single.businessProfile.displayName, 'Fashion');
    expect(page.events.single.sourceId, 's1');
    expect(page.events.single.amount.minorUnits, 1250);
    expect(page.events.single.profit.minorUnits, 400);
  });

  test('malformed money and dates remain safe at the network boundary', () {
    final event = CrossShopActivity.fromJson({
      'eventId': 'activity:a1',
      'sourceId': '1',
      'tenantId': 'shop-1',
      'businessProfile': 'duka',
      'amountMinor': 'bad',
      'profitMinor': null,
      'createdAt': 'bad',
    });

    expect(event.amount.minorUnits, 0);
    expect(event.profit.minorUnits, 0);
    expect(event.createdAt.millisecondsSinceEpoch, 0);
  });

  test('activity cursors preserve timestamp and stable event identity', () {
    final event = CrossShopActivity.fromJson({
      'eventId': 'sale:same-time-2',
      'sourceId': 'same-time-2',
      'tenantId': 'shop-1',
      'businessProfile': 'duka',
      'createdAt': '2026-10-25T10:00:00.000Z',
    });
    final page = CrossShopActivityPage(events: [event]);
    expect(CrossShopActivityPage.cursorFor(page.events.single),
        '2026-10-25T10:00:00.000Z|sale:same-time-2');
  });
}
