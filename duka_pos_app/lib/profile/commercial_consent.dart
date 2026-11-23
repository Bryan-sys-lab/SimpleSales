import 'dart:convert';
import 'dart:math';

class CommercialConsentGrant {
  static String createGrantUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final value = bytes.map(hex).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
  }
  const CommercialConsentGrant({
    required this.grantUuid,
    required this.status,
    required this.scopes,
    required this.noticeVersion,
    required this.noticeDigest,
    required this.schemaVersion,
    required this.dictionaryVersion,
    required this.appVersion,
    required this.captureMethod,
    required this.authorityEvidence,
    required this.effectiveAtUtc,
    this.withdrawnAtUtc,
  });

  static const allowedScopes = <String>[
    'business_activity',
    'product_demand',
    'availability',
    'procurement_patterns',
    'operating_cost_bands',
    'digitisation_metrics',
  ];

  final String grantUuid;
  final String status;
  final List<String> scopes;
  final String noticeVersion;
  final String noticeDigest;
  final String schemaVersion;
  final String dictionaryVersion;
  final String appVersion;
  final String captureMethod;
  final String authorityEvidence;
  final String effectiveAtUtc;
  final String? withdrawnAtUtc;

  Map<String, Object?> toRow() => {
        'grant_uuid': grantUuid,
        'status': status,
        'scopes_json': jsonEncode(scopes),
        'notice_version': noticeVersion,
        'notice_digest': noticeDigest,
        'schema_version': schemaVersion,
        'dictionary_version': dictionaryVersion,
        'app_version': appVersion,
        'capture_method': captureMethod,
        'authority_evidence': authorityEvidence,
        'effective_at_utc': effectiveAtUtc,
        'withdrawn_at_utc': withdrawnAtUtc,
      };

  factory CommercialConsentGrant.fromRow(Map<String, Object?> row) {
    final decoded = jsonDecode(row['scopes_json'] as String? ?? '[]');
    return CommercialConsentGrant(
      grantUuid: row['grant_uuid'] as String,
      status: row['status'] as String,
      scopes: decoded is List
          ? decoded.whereType<String>().where(allowedScopes.toSet().contains).toList()
          : const [],
      noticeVersion: row['notice_version'] as String,
      noticeDigest: row['notice_digest'] as String,
      schemaVersion: row['schema_version'] as String,
      dictionaryVersion: row['dictionary_version'] as String,
      appVersion: row['app_version'] as String,
      captureMethod: row['capture_method'] as String,
      authorityEvidence: row['authority_evidence'] as String,
      effectiveAtUtc: row['effective_at_utc'] as String,
      withdrawnAtUtc: row['withdrawn_at_utc'] as String?,
    );
  }

  void validate() {
    if (scopes.isEmpty || scopes.toSet().length != scopes.length ||
        scopes.any((scope) => !CommercialConsentGrant.allowedScopes.contains(scope))) {
      throw ArgumentError('Commercial consent scopes must be explicit and unique.');
    }
    if (status != 'active' && status != 'withdrawn') {
      throw ArgumentError('Unsupported commercial consent status.');
    }
    if (!noticeDigest.startsWith('sha256:') ||
        noticeDigest.length != 71 ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(noticeDigest)) {
      throw ArgumentError('Consent notice evidence requires a SHA-256 digest.');
    }
  }
}
