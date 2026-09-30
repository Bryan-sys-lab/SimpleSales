import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Encrypts exported backup bytes with AES-256-GCM. The per-install key is
/// kept in the OS keystore/keychain, never in SharedPreferences or the file.
/// This protects local backup files from casual file-system/cloud inspection.
/// It is not a substitute for a server KMS: a copy of the key and file made
/// before erasure cannot be revoked by this device.
class EncryptedBackupService {
  static const _keyName = 'duka_backup_key_v1';
  static const _format = 'duka-encrypted-backup-v1';
  static const _storage = FlutterSecureStorage();
  static final _cipher = AesGcm.with256bits();

  static Future<SecretKey> _key() async {
    final existing = await _storage.read(key: _keyName);
    if (existing != null) {
      return _cipher.newSecretKeyFromBytes(base64Url.decode(existing));
    }
    final key = await _cipher.newSecretKey();
    final bytes = await key.extractBytes();
    await _storage.write(key: _keyName, value: base64UrlEncode(bytes));
    return key;
  }

  static Future<File> encryptToFile(List<int> clearBytes,
      {String prefix = 'duka-backup'}) async {
    final key = await _key();
    final box = await _cipher.encrypt(clearBytes,
        secretKey: key, nonce: _cipher.newNonce());
    final payload = jsonEncode({
      'format': _format,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'nonce': base64UrlEncode(box.nonce),
      'cipherText': base64UrlEncode(box.cipherText),
      'mac': base64UrlEncode(box.mac.bytes),
    });
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
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.duka')) {
        await entity.delete();
      }
    }
  }
}
