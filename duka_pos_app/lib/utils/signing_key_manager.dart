import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the signing keystore information
/// IMPORTANT: This does NOT store the actual keystore file
/// It only stores metadata about where the keystore is backed up
class SigningKeyManager {
  static const _storage = FlutterSecureStorage();
  static const _keystoreInfoKey = 'signing_keystore_info';

  /// Store information about where keystore is backed up
  static Future<void> saveKeystoreInfo({
    required String backupLocation,
    required String alias,
    required DateTime created,
  }) async {
    await _storage.write(
      key: _keystoreInfoKey,
      value: '$backupLocation|$alias|${created.toIso8601String()}',
    );
  }

  /// Retrieve keystore backup information
  static Future<KeystoreInfo?> getKeystoreInfo() async {
    final data = await _storage.read(key: _keystoreInfoKey);
    if (data == null) return null;

    final parts = data.split('|');
    if (parts.length != 3) return null;

    return KeystoreInfo(
      backupLocation: parts[0],
      alias: parts[1],
      created: DateTime.parse(parts[2]),
    );
  }
}

class KeystoreInfo {
  final String backupLocation;
  final String alias;
  final DateTime created;

  KeystoreInfo({
    required this.backupLocation,
    required this.alias,
    required this.created,
  });
}

/// INSTRUCTIONS FOR SECURE KEYSTORE MANAGEMENT:
///
/// 1. Generate keystore ONCE:
///    keytool -genkey -v -keystore duka-pos-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias duka-pos
///
/// 2. Store keystore in MULTIPLE secure locations:
///    - Password manager (1Password, Bitwarden, etc.)
///    - Encrypted cloud storage (Google Drive with 2FA)
///    - USB drive in safe/secure location
///    - NEVER in git repository or source code
///
/// 3. Record passwords securely:
///    - Keystore password
///    - Key alias password
///    - Store in password manager with backup codes
///
/// 4. Create backup signing instructions:
///    - Document step-by-step how to sign APK
///    - Include in team documentation
///    - Test recovery process once
///
/// 5. If keystore is lost:
///    - All future updates require fresh install
///    - All user data (local SQLite) will be lost
///    - This is why multiple backups are CRITICAL
