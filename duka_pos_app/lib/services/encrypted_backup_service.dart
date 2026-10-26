import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show compute, immutable, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/crypto_utils.dart';

/// Arguments for [buildEncryptedPayload]. Plain data only — this is what
/// crosses the isolate boundary.
///
/// Declared at the top level because Dart has no nested classes, and because a
/// `compute` payload has to be a type the sending isolate can construct.
@immutable
class EncryptRequest {
  const EncryptRequest(this.keyBytes, this.clearBytes);
  final List<int> keyBytes;
  final List<int> clearBytes;
}

/// Plain arguments for the passphrase KDF isolate. Keeping the expensive KDF
/// off the UI isolate matters on a till: the portable format intentionally
/// uses a high iteration count, so a backup must not make the checkout stop
/// responding while it is being written or restored.
@immutable
class PortableCryptoRequest {
  const PortableCryptoRequest({
    required this.clearBytes,
    required this.passphrase,
    required this.salt,
    this.decrypt = false,
    this.envelope,
  });

  final List<int>? clearBytes;
  final String passphrase;
  final List<int> salt;
  final bool decrypt;
  final Map<String, dynamic>? envelope;
}

const _portableIterations = 600000;
const _portableFormat = 'duka-encrypted-backup-v2';

Future<String> _encryptPortableInIsolate(PortableCryptoRequest request) async {
  final cipher = AesGcm.with256bits();
  final key = await Pbkdf2.hmacSha256(
    iterations: _portableIterations,
    bits: 256,
  ).deriveKeyFromPassword(
    password: request.passphrase,
    nonce: request.salt,
  );
  final clear = request.clearBytes!;
  final box = await cipher.encrypt(clear, secretKey: key);
  final digest = await Sha256().hash(clear);
  return jsonEncode({
    'format': _portableFormat,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'kdf': 'pbkdf2-sha256',
    'iterations': _portableIterations,
    'salt': base64UrlEncode(request.salt),
    'nonce': base64UrlEncode(box.nonce),
    'cipherText': base64UrlEncode(box.cipherText),
    'mac': base64UrlEncode(box.mac.bytes),
    'manifest': {
      'clearBytes': clear.length,
      'sha256': base64UrlEncode(digest.bytes),
    },
  });
}

Future<List<int>> _decryptPortableInIsolate(
    PortableCryptoRequest request) async {
  final envelope = request.envelope!;
  final cipher = AesGcm.with256bits();
  final key = await Pbkdf2.hmacSha256(
    iterations: _portableIterations,
    bits: 256,
  ).deriveKeyFromPassword(
    password: request.passphrase,
    nonce: request.salt,
  );
  final clear = await cipher.decrypt(
    SecretBox(
      base64Url.decode(envelope['cipherText'] as String),
      nonce: base64Url.decode(envelope['nonce'] as String),
      mac: Mac(base64Url.decode(envelope['mac'] as String)),
    ),
    secretKey: key,
  );
  final manifest = envelope['manifest'];
  if (manifest is! Map || manifest['clearBytes'] != clear.length) {
    throw const FormatException('Portable backup manifest does not match');
  }
  final digest = await Sha256().hash(clear);
  if (manifest['sha256'] != base64UrlEncode(digest.bytes)) {
    throw const FormatException('Portable backup integrity check failed');
  }
  return clear;
}

/// Encrypts exported backup bytes with AES-256-GCM. The per-install key is
/// kept in the OS keystore/keychain, never in SharedPreferences or the file.
/// This protects local backup files from casual file-system/cloud inspection.
/// It is not a substitute for a server KMS: a copy of the key and file made
/// before erasure cannot be revoked by this device.
class EncryptedBackupService {
  static const _keyName = 'duka_backup_key_v1';
  static const _format = 'duka-encrypted-backup-v1';

  /// The keystore. Injectable so a test can substitute an in-memory one; the
  /// production build never touches this.
  ///
  /// The seam exists at the keystore rather than at the cipher on purpose: the
  /// cipher, the framing and the `compute` hop are the very things a backup
  /// round trip depends on, and a test that mocks THEM away proves nothing.
  /// `flutter_secure_storage` is the only platform-bound part, and the only part
  /// a test genuinely cannot drive.
  @visibleForTesting
  static FlutterSecureStorage? storageForTest;

  static FlutterSecureStorage get _storage =>
      storageForTest ?? const FlutterSecureStorage();

  static final _cipher = AesGcm.with256bits();
  static const _portableFormat = 'duka-encrypted-backup-v2';
  static const _portableIterations = 600000;

  /// Raw key bytes, read from or created in the OS keystore. Kept separate
  /// from the cipher so the expensive step can be dispatched to another
  /// isolate: every other part of this file needs a platform channel, and
  /// those are not registered inside a `compute` isolate.
  static Future<List<int>> _keyBytes() async {
    final existing = await _storage.read(key: _keyName);
    if (existing != null) {
      return base64Url.decode(existing);
    }
    final key = await _cipher.newSecretKey();
    final bytes = await key.extractBytes();
    await _storage.write(key: _keyName, value: base64UrlEncode(bytes));
    return bytes;
  }

  static Future<SecretKey> _key() async =>
      _cipher.newSecretKeyFromBytes(await _keyBytes());

  /// The key bytes, for a test that must prove the key is STABLE.
  ///
  /// A new key per run would make last week's backup undecryptable — the
  /// quietest possible way for a backup scheme to fail, because nothing errors
  /// until the day someone actually tries to restore.
  @visibleForTesting
  static Future<List<int>> keyBytesForTest() => _keyBytes();

  /// The CPU-bound half of [encryptToFile]: AES-256-GCM over a whole workbook.
  ///
  /// Top-level and plugin-free so it can run in a background isolate — this is
  /// the part that would otherwise stall the till's frame loop during an
  /// automatic backup. Reading the key and writing the result must happen on
  /// the main isolate, where `flutter_secure_storage` and `path_provider` are
  /// actually bound.
  static Future<String> buildEncryptedPayload(EncryptRequest request) async {
    final cipher = AesGcm.with256bits();
    final key = await cipher.newSecretKeyFromBytes(request.keyBytes);
    final box = await cipher.encrypt(request.clearBytes,
        secretKey: key, nonce: cipher.newNonce());
    return jsonEncode({
      'format': _format,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'nonce': base64UrlEncode(box.nonce),
      'cipherText': base64UrlEncode(box.cipherText),
      'mac': base64UrlEncode(box.mac.bytes),
    });
  }

  static Future<File> encryptToFile(List<int> clearBytes,
      {String prefix = 'duka-backup'}) async {
    final keyBytes = await _keyBytes();
    final payload = await compute(
        buildEncryptedPayload, EncryptRequest(keyBytes, clearBytes));
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/$prefix-${DateTime.now().toIso8601String().substring(0, 10)}.duka');
    await file.writeAsString(payload, flush: true);
    return file;
  }

  /// Builds the same device-bound encrypted envelope as a local backup,
  /// without requiring a filesystem. Used when an opaque ciphertext snapshot
  /// is uploaded to the tenant's cloud backup endpoint.
  static Future<String> encryptBytes(List<int> clearBytes) async {
    final keyBytes = await _keyBytes();
    return compute(
      buildEncryptedPayload,
      EncryptRequest(keyBytes, clearBytes),
    );
  }

  static Future<List<int>> decryptBytes(List<int> encodedBytes) async {
    final value = jsonDecode(utf8.decode(encodedBytes));
    if (value is! Map || value['format'] != _format) {
      throw const FormatException('Unsupported encrypted backup');
    }
    final key = await _key();
    final box = SecretBox(
      base64Url.decode(value['cipherText'] as String),
      nonce: base64Url.decode(value['nonce'] as String),
      mac: Mac(base64Url.decode(value['mac'] as String)),
    );
    return _cipher.decrypt(box, secretKey: key);
  }

  /// Portable backup format. The passphrase, not this handset's keystore,
  /// derives the key, so the file can be restored on another phone.
  static Future<String> buildPortablePayload({
    required List<int> clearBytes,
    required String passphrase,
  }) async {
    if (passphrase.length < 8) {
      throw const FormatException('Backup passphrase must be at least 8 characters');
    }
    final salt = randomBytes(16);
    return compute(
      _encryptPortableInIsolate,
      PortableCryptoRequest(
        clearBytes: clearBytes,
        passphrase: passphrase,
        salt: salt,
      ),
    );
  }

  static Future<List<int>> decryptPortableBytes({
    required List<int> encodedBytes,
    required String passphrase,
  }) async {
    final value = jsonDecode(utf8.decode(encodedBytes));
    if (value is! Map || value['format'] != _portableFormat ||
        value['kdf'] != 'pbkdf2-sha256' ||
        value['iterations'] != _portableIterations) {
      throw const FormatException('Unsupported portable encrypted backup');
    }
    return compute(
      _decryptPortableInIsolate,
      PortableCryptoRequest(
        clearBytes: null,
        passphrase: passphrase,
        salt: base64Url.decode(value['salt'] as String),
        decrypt: true,
        envelope: Map<String, dynamic>.from(value),
      ),
    );
  }

  static Future<File> encryptPortableToFile(
    List<int> clearBytes, {
    required String passphrase,
    String prefix = 'duka-backup',
  }) async {
    final payload = await buildPortablePayload(
      clearBytes: clearBytes,
      passphrase: passphrase,
    );
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/$prefix-${DateTime.now().toIso8601String().substring(0, 10)}.duka');
    await file.writeAsString(payload, flush: true);
    return file;
  }

  static Future<List<int>?> pickAndDecrypt() async {
    final files = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['duka']);
    if (files.isEmpty) return null;
    final file = files.single;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('The encrypted backup could not be read');
    }
    return decryptBytes(bytes);
  }

  /// Irreversibly removes the local decryption key and generated encrypted
  /// backup files. Shared/off-device copies may still exist and require KMS
  /// key destruction plus restore filtering for legal cryptographic erasure.
  ///
  /// ## WHY IT RETURNS A COUNT
  ///
  /// "The backups are erased" is a claim the owner cannot check. "Three
  /// backup files were erased" is a claim they can, and the difference matters
  /// on a till where the whole point of pressing the button is to be sure.
  ///
  /// ## WHY IT NEVER THROWS
  ///
  /// A missing documents directory, a file the OS has locked, a keystore that
  /// refuses a delete: none of those is a reason to fail the whole operation
  /// with nothing erased and nothing said. Each is counted and reported, and
  /// the key — the part that actually makes the files unreadable — is deleted
  /// first, so a failure part-way through still leaves the backups
  /// undecryptable.
  static Future<BackupErasureResult> cryptographicEraseLocalBackups() async {
    // The key first. It is what makes every `.duka` file unreadable, and it is
    // the part that cannot be recovered by restoring a file.
    bool keyDeleted = true;
    try {
      await _storage.delete(key: _keyName);
    } on Object catch (_) {
      keyDeleted = false;
    }

    int filesErased = 0;
    final List<String> failures = <String>[];
    try {
      final dir = await getApplicationDocumentsDirectory();
      // Async enumeration: `listSync` walks the whole directory synchronously
      // and would stall the frame loop on a till with many retained backups.
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.duka')) {
          try {
            await entity.delete();
            filesErased++;
          } on Object catch (_) {
            failures.add(entity.path);
          }
        }
      }
    } on Object catch (_) {
      // The directory could not be listed — a device with no documents folder,
      // or a storage error. The key is already gone, so anything in there is
      // unreadable regardless.
      failures.add('directory');
    }

    return BackupErasureResult(
      filesErased: filesErased,
      keyDeleted: keyDeleted,
      failures: failures.length,
    );
  }
}

/// What an erasure of the local backups actually did.
class BackupErasureResult {
  const BackupErasureResult({
    required this.filesErased,
    required this.keyDeleted,
    required this.failures,
  });

  /// How many `.duka` files were deleted.
  final int filesErased;

  /// Whether the decryption key was destroyed.
  final bool keyDeleted;

  /// How many things could not be removed.
  final int failures;

  /// Whether the operation fully succeeded.
  bool get complete => keyDeleted && failures == 0;
}
