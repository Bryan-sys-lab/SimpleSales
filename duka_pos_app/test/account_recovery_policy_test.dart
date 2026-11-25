import 'package:duka_pos/screens/account_recovery_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote shop login does not require a backup passphrase', () {
    expect(
      accountRecoveryPathForPassphrase(''),
      AccountRecoveryPath.cloudSync,
    );
  });

  test('a supplied backup passphrase must meet the portable format minimum',
      () {
    expect(accountRecoveryPathForPassphrase('short'), isNull);
    expect(
      accountRecoveryPathForPassphrase('long-enough'),
      AccountRecoveryPath.portableBackup,
    );
  });
}
