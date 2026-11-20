import 'dart:convert';
import 'kesic_reference_2020.dart';

/// Structured, owner-confirmed context for one workspace.
///
/// This is operational shop data. It does not imply commercial contribution
/// consent. It may sync to the shop's operational tenant record and be included
/// in the separately disclosed owner backup; it is never sent through
/// telemetry or commercial contribution sync.
class BusinessContext {
  const BusinessContext({
    this.appProfile = 'duka',
    this.primaryActivityCode,
    this.primaryActivityStatus = 'pending',
    this.activityScheme,
    this.activityVersion,
    this.secondaryActivityCodes = const [],
    this.operatorRoles = const [],
    this.salesChannels = const [],
    this.countyCode,
    this.settlementContext = 'unknown',
    this.fieldProvenance = const {},
    this.confirmedAtUtc,
    this.schemaVersion = 1,
  });

  final String? primaryActivityCode;

  /// Read-only POS setup preset, independent from KeSIC economic activity.
  final String appProfile;

  /// `selected`, `pending`, or `prefer_not_to_say`; null codes are not
  /// interchangeable with an owner declining to classify.
  final String primaryActivityStatus;
  final String? activityScheme;
  final String? activityVersion;
  final List<String> secondaryActivityCodes;
  final List<String> operatorRoles;
  final List<String> salesChannels;
  final String? countyCode;
  final String settlementContext;
  final Map<String, String> fieldProvenance;
  final String? confirmedAtUtc;
  final int schemaVersion;

  static const operatorRoleValues = <String>{
    'producer',
    'manufacturer',
    'importer',
    'distributor',
    'wholesaler',
    'retailer',
    'service_provider',
    'mixed',
    'other',
  };
  static const salesChannelValues = <String>{
    'physical_shop',
    'market_stall',
    'mobile_route',
    'online_store',
    'social_commerce',
    'wholesale',
    'delivery',
    'other',
  };
  static const settlementValues = <String>{
    'urban',
    'peri_urban',
    'rural',
    'unknown',
    'prefer_not_to_say',
  };

  factory BusinessContext.fromMap(Map<String, Object?> row) {
    List<String> list(String key) {
      final value = jsonDecode(row[key] as String? ?? '[]');
      if (value is! List) return const [];
      return value.whereType<String>().toList(growable: false);
    }

    final provenance =
        jsonDecode(row['field_provenance_json'] as String? ?? '{}');
    return BusinessContext(
      appProfile: row['app_profile'] as String? ?? 'duka',
      primaryActivityCode: row['primary_activity_code'] as String?,
      primaryActivityStatus:
          row['primary_activity_status'] as String? ?? 'pending',
      activityScheme: row['activity_scheme'] as String?,
      activityVersion: row['activity_version'] as String?,
      secondaryActivityCodes: list('secondary_activity_codes_json'),
      operatorRoles: list('operator_roles_json'),
      salesChannels: list('sales_channels_json'),
      countyCode: row['county_code'] as String?,
      settlementContext: row['settlement_context'] as String? ?? 'unknown',
      fieldProvenance: provenance is Map
          ? provenance
              .map((key, value) => MapEntry(key.toString(), value.toString()))
          : const {},
      confirmedAtUtc: row['confirmed_at_utc'] as String?,
      schemaVersion: row['schema_version'] as int? ?? 1,
    );
  }

  Map<String, Object?> toRow({required String updatedAtUtc}) {
    validate();
    return {
      'id': 1,
      'app_profile': appProfile,
      'primary_activity_status': primaryActivityStatus,
      'primary_activity_code': primaryActivityCode,
      'activity_scheme': primaryActivityCode == null ? null : 'KESIC',
      'activity_version': primaryActivityCode == null ? null : activityVersion,
      'secondary_activity_codes_json': jsonEncode(secondaryActivityCodes),
      'operator_roles_json': jsonEncode(operatorRoles),
      'sales_channels_json': jsonEncode(salesChannels),
      'county_code': countyCode,
      'settlement_context': settlementContext,
      'field_provenance_json': jsonEncode(fieldProvenance),
      'confirmed_at_utc': confirmedAtUtc,
      'schema_version': schemaVersion,
      'updated_at_utc': updatedAtUtc,
    };
  }

  void validate() {
    if (!const {'drinks', 'duka', 'fashion', 'open'}.contains(appProfile)) {
      throw ArgumentError('Choose one of the four supported POS profiles.');
    }
    if (!const {'selected', 'pending', 'prefer_not_to_say'}
            .contains(primaryActivityStatus) ||
        (primaryActivityStatus == 'selected' && primaryActivityCode == null) ||
        (primaryActivityStatus == 'prefer_not_to_say' &&
            primaryActivityCode != null)) {
      throw ArgumentError('Choose an activity, keep it pending, or decline.');
    }
    if (secondaryActivityCodes.length > 4 ||
        secondaryActivityCodes.toSet().length !=
            secondaryActivityCodes.length ||
        secondaryActivityCodes.contains(primaryActivityCode)) {
      throw ArgumentError('Choose up to four distinct secondary activities.');
    }
    if (primaryActivityCode != null &&
        ((activityScheme != null && activityScheme != 'KESIC') ||
            !RegExp(r'^\d{2,6}$')
                .hasMatch(primaryActivityCode!.trim()) ||
            activityVersion == null ||
            activityVersion!.trim().isEmpty)) {
      throw ArgumentError('An activity code requires its reference version.');
    }
    if (primaryActivityStatus == 'selected' &&
        !isCachedKesicCode(primaryActivityCode ?? '')) {
      throw ArgumentError('Only a code in the selected KeSIC reference can be confirmed.');
    }
    if (countyCode != null &&
        !RegExp(r'^0(0[1-9]|[1-3][0-9]|4[0-7])$').hasMatch(countyCode!)) {
      throw ArgumentError('Choose a valid Kenya county code.');
    }
    const provenanceValues = {
      'owner_confirmed',
      'staff_entered',
      'imported',
      'system_derived',
      'admin_reviewed',
    };
    if (fieldProvenance.values
        .any((value) => !provenanceValues.contains(value))) {
      throw ArgumentError('Business details have unsupported provenance.');
    }
    if (!operatorRoleValues.containsAll(operatorRoles) ||
        !salesChannelValues.containsAll(salesChannels) ||
        !settlementValues.contains(settlementContext)) {
      throw ArgumentError('Business context contains an unsupported value.');
    }
  }
}
