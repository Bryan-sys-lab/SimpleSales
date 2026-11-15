import 'package:duka_pos/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a stored hash asking for an absurd iteration count is refused fast',
      () async {
    final stopwatch = Stopwatch()..start();
    final ok = await AuthService.verifyPin(
      '123456',
      'pbkdf2\$999999999\$AAAAAAAAAAAAAAAAAAAAAA==\$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    );
    expect(ok, isFalse);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('the iteration ceiling sits above every work factor in use', () {
    expect(AuthService.maxStoredIterations, greaterThanOrEqualTo(600000));
  });
}
