import 'package:duka_pos/profile/shop_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the four authoritative profiles are accepted', () {
    expect(ShopProfile.values.map((profile) => profile.wireValue),
        ['drinks', 'duka', 'fashion', 'open']);
  });

  test('unknown and missing legacy values resolve to Duka', () {
    expect(ShopProfile.fromWire(null), ShopProfile.duka);
    expect(ShopProfile.fromWire('generalRetail'), ShopProfile.duka);
    expect(ShopProfile.fromWire('duka'), ShopProfile.duka);
  });

  test('wire values round-trip without creating profile-specific schemas', () {
    for (final profile in ShopProfile.values) {
      expect(ShopProfile.fromWire(profile.wireValue), profile);
    }
  });
}
