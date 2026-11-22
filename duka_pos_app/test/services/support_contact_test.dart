import 'package:duka_pos/services/support_contact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the verified backend WhatsApp URL as a fallback', () {
    final Uri? uri = SupportContact.whatsappUri(
      message: 'Help me activate my shop',
      fallbackUrl: 'https://wa.me/254712345678',
    );

    expect(uri?.host, 'wa.me');
    expect(uri?.pathSegments, <String>['254712345678']);
    expect(uri?.queryParameters['text'], 'Help me activate my shop');
  });

  test('rejects non-WhatsApp or malformed fallback URLs', () {
    expect(
      SupportContact.whatsappUri(
        message: 'Help',
        fallbackUrl: 'https://example.com/254712345678',
      ),
      isNull,
    );
    expect(
      SupportContact.whatsappUri(
        message: 'Help',
        fallbackUrl: 'https://wa.me/not-a-number',
      ),
      isNull,
    );
  });
}
