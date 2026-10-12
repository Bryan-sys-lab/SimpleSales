import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show compute, immutable, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

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
  static Future<void> cryptographicEraseLocalBackups() async {
    await _storage.delete(key: _keyName);
    final dir = await getApplicationDocumentsDirectory();
    // Async enumeration: `listSync` walks the whole directory synchronously
    // and would stall the frame loop on a till with many retained backups.
    final entities = await dir.list().toList();
    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.duka')) {
        await entity.delete();
      }
    }
  }
}
