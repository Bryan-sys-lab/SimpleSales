library;

import 'dart:math';

/// Cryptographically secure random bytes of [length].
///
/// Centralized so the salt/nonce generation in [EncryptedBackupService],
/// [AuthService], and [StaffCredentialCache] share one implementation rather
/// than drifting apart.
List<int> randomBytes(int length) =>
    List<int>.generate(length, (_) => Random.secure().nextInt(256));

/// A UUID v4 string generated from cryptographically secure random bytes.
///
/// Used by both [TelemetryService] (device id) and [SupportService]
/// (support device id) so a change to the v4 masking lands in both places.
String generateUuid() {
  final bytes = randomBytes(16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
  final hex =
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('');
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}
