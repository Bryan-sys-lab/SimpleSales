import '../utils/money.dart';

class TaxRuleSnapshot {
  const TaxRuleSnapshot({
    required this.id,
    required this.taxType,
    required this.scope,
    required this.jurisdiction,
    required this.rateBasisPoints,
    required this.version,
    required this.taxBase,
    required this.threshold,
    required this.effectiveFrom,
    required this.effectiveTo,
    required this.sourceUrl,
    required this.sourceReference,
    required this.reviewedAt,
    required this.status,
  });

  final String id;
  final String taxType;
  final String scope;
  final String jurisdiction;
  final int? rateBasisPoints;
  final int version;
  final String taxBase;
  final Money? threshold;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String sourceUrl;
  final String? sourceReference;
  final DateTime? reviewedAt;
  final String status;

  int? get vatRatePercent {
    if (taxType != 'vat' ||
        rateBasisPoints == null ||
        rateBasisPoints! % 100 != 0) {
      return null;
    }
    return rateBasisPoints! ~/ 100;
  }

  factory TaxRuleSnapshot.fromJson(Map<String, dynamic> json) {
    return TaxRuleSnapshot(
      id: json['id'] as String? ?? '',
      taxType: json['tax_type'] as String? ?? '',
      scope: json['scope'] as String? ?? '',
      jurisdiction: json['jurisdiction'] as String? ?? 'KE',
      rateBasisPoints: (json['rate_basis_points'] as num?)?.toInt(),
      version: (json['version'] as num?)?.toInt() ?? 1,
      taxBase: json['tax_base'] as String? ?? 'none',
      threshold: json['threshold_minor'] == null
          ? null
          : Money.fromMinor((json['threshold_minor'] as num).toInt()),
      effectiveFrom:
          DateTime.tryParse(json['effective_from'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      effectiveTo: DateTime.tryParse(json['effective_to'] as String? ?? ''),
      sourceUrl: json['source_url'] as String? ?? '',
      sourceReference: json['source_reference'] as String?,
      reviewedAt: DateTime.tryParse(json['reviewed_at'] as String? ?? ''),
      status: json['status'] as String? ?? 'needs_review',
    );
  }
}

class VatReportSnapshot {
  const VatReportSnapshot({
    required this.outputVat,
    required this.creditNoteVat,
    required this.adjustedOutputVat,
    required this.linesWithoutRuleSnapshot,
    required this.status,
  });

  final Money outputVat;
  final Money creditNoteVat;
  final Money adjustedOutputVat;
  final int linesWithoutRuleSnapshot;
  final String status;

  factory VatReportSnapshot.fromJson(Map<String, dynamic> json) {
    return VatReportSnapshot(
      outputVat:
          Money.fromMinor((json['output_vat_minor'] as num?)?.toInt() ?? 0),
      creditNoteVat: Money.fromMinor(
          (json['credit_note_vat_minor'] as num?)?.toInt() ?? 0),
      adjustedOutputVat: Money.fromMinor(
          (json['adjusted_output_vat_minor'] as num?)?.toInt() ?? 0),
      linesWithoutRuleSnapshot:
          (json['lines_without_rule_snapshot'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'needs_review',
    );
  }
}

class InputVatReportSnapshot {
  const InputVatReportSnapshot({
    required this.eligibleInputVat,
    required this.evidenceCount,
    required this.unmatchedCount,
    required this.overdueCount,
    required this.status,
  });

  final Money eligibleInputVat;
  final int evidenceCount;
  final int unmatchedCount;
  final int overdueCount;
  final String status;

  factory InputVatReportSnapshot.fromJson(Map<String, dynamic> json) {
    return InputVatReportSnapshot(
      eligibleInputVat: Money.fromMinor(
          (json['eligible_input_vat_minor'] as num?)?.toInt() ?? 0),
      evidenceCount: (json['evidence_count'] as num?)?.toInt() ?? 0,
      unmatchedCount: (json['unmatched_count'] as num?)?.toInt() ?? 0,
      overdueCount: (json['overdue_count'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'needs_review',
    );
  }
}

class VatReturnSnapshot {
  const VatReturnSnapshot({
    required this.outputVat,
    required this.eligibleInputVat,
    required this.adjustments,
    required this.netPayable,
    required this.status,
    required this.periodStart,
    required this.periodEnd,
  });

  final Money outputVat;
  final Money eligibleInputVat;
  final Money adjustments;
  final Money netPayable;
  final String status;
  final DateTime periodStart;
  final DateTime periodEnd;

  factory VatReturnSnapshot.fromJson(Map<String, dynamic> json) {
    return VatReturnSnapshot(
      outputVat:
          Money.fromMinor((json['output_vat_minor'] as num?)?.toInt() ?? 0),
      eligibleInputVat: Money.fromMinor(
          (json['eligible_input_vat_minor'] as num?)?.toInt() ?? 0),
      adjustments:
          Money.fromMinor((json['adjustments_minor'] as num?)?.toInt() ?? 0),
      netPayable:
          Money.fromMinor((json['net_payable_minor'] as num?)?.toInt() ?? 0),
      status: json['status'] as String? ?? 'prepared',
      periodStart: DateTime.tryParse(json['period_start'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      periodEnd: DateTime.tryParse(json['period_end'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class EtimsQueueSnapshot {
  const EtimsQueueSnapshot({
    required this.issued,
    required this.pending,
    required this.rejected,
    required this.status,
  });

  final int issued;
  final int pending;
  final int rejected;
  final String status;

  factory EtimsQueueSnapshot.fromJson(Map<String, dynamic> json) {
    return EtimsQueueSnapshot(
      issued: (json['issued'] as num?)?.toInt() ?? 0,
      pending: (json['pending'] as num?)?.toInt() ?? 0,
      rejected: (json['rejected'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'clear',
    );
  }
}

class ConditionalObligationSnapshot {
  const ConditionalObligationSnapshot({
    required this.taxType,
    required this.registered,
    required this.reviewedRuleCount,
    required this.status,
  });

  final String taxType;
  final bool registered;
  final int reviewedRuleCount;
  final String status;

  factory ConditionalObligationSnapshot.fromJson(Map<String, dynamic> json) {
    return ConditionalObligationSnapshot(
      taxType: json['tax_type'] as String? ?? '',
      registered: json['registered'] as bool? ?? false,
      reviewedRuleCount: (json['reviewed_rule_count'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'not_registered',
    );
  }
}

class TotReturnSnapshot {
  const TotReturnSnapshot({
    required this.grossSales,
    required this.estimate,
    required this.rateBasisPoints,
    required this.status,
    required this.periodStart,
    required this.periodEnd,
  });

  final Money grossSales;
  final Money estimate;
  final int? rateBasisPoints;
  final String status;
  final DateTime periodStart;
  final DateTime periodEnd;

  factory TotReturnSnapshot.fromJson(Map<String, dynamic> json) {
    return TotReturnSnapshot(
      grossSales:
          Money.fromMinor((json['gross_sales_minor'] as num?)?.toInt() ?? 0),
      estimate: Money.fromMinor((json['estimate_minor'] as num?)?.toInt() ?? 0),
      rateBasisPoints: (json['rate_basis_points'] as num?)?.toInt(),
      status: json['status'] as String? ?? 'prepared',
      periodStart: DateTime.tryParse(json['period_start'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      periodEnd: DateTime.tryParse(json['period_end'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

/// The safe tax-entity projection returned by the backend. The KRA PIN itself
/// never crosses this boundary; only whether it is set and its last four are
/// displayed to the owner.
class TaxEntitySnapshot {
  const TaxEntitySnapshot({
    required this.id,
    required this.legalForm,
    required this.displayLabel,
    required this.kraPinSet,
    required this.kraPinLast4,
    required this.obligations,
    required this.accountingPeriodStartMonth,
    required this.status,
    this.etimsOnboardingStatus = 'not_started',
    this.etimsMethod,
    this.outletReference,
    this.linkedShopCount = 0,
    this.turnover = Money.zero,
    this.thresholdStatus,
    this.rules = const <TaxRuleSnapshot>[],
    this.totEstimate,
    this.totDueDate,
    this.totStatus,
    this.vatReport,
    this.inputVatReport,
    this.vatReturn,
    this.etimsQueue,
    this.totReturn,
    this.conditionalObligations = const <ConditionalObligationSnapshot>[],
  });

  final String id;
  final String legalForm;
  final String displayLabel;
  final bool kraPinSet;
  final String? kraPinLast4;
  final List<String> obligations;
  final int accountingPeriodStartMonth;
  final String status;
  final String etimsOnboardingStatus;
  final String? etimsMethod;
  final String? outletReference;
  final int linkedShopCount;
  final Money turnover;
  final String? thresholdStatus;
  final List<TaxRuleSnapshot> rules;
  final Money? totEstimate;
  final DateTime? totDueDate;
  final String? totStatus;
  final VatReportSnapshot? vatReport;
  final InputVatReportSnapshot? inputVatReport;
  final VatReturnSnapshot? vatReturn;
  final EtimsQueueSnapshot? etimsQueue;
  final TotReturnSnapshot? totReturn;
  final List<ConditionalObligationSnapshot> conditionalObligations;

  TaxRuleSnapshot? get currentVatRule {
    for (final rule in rules) {
      if (rule.taxType == 'vat' && rule.status == 'active') return rule;
    }
    return null;
  }

  int? get managedVatRatePercent => currentVatRule?.vatRatePercent;

  factory TaxEntitySnapshot.fromResponse(Map<String, dynamic> response) {
    final entity = Map<String, dynamic>.from(
      (response['tax_entity'] as Map?) ?? const <String, dynamic>{},
    );
    final threshold = Map<String, dynamic>.from(
      (response['threshold'] as Map?) ?? const <String, dynamic>{},
    );
    final mapping = Map<String, dynamic>.from(
      (response['mapping'] as Map?) ?? const <String, dynamic>{},
    );
    final totReport = Map<String, dynamic>.from(
      (response['tot_report'] as Map?) ?? const <String, dynamic>{},
    );
    final obligationReport = Map<String, dynamic>.from(
      (response['obligation_report'] as Map?) ?? const <String, dynamic>{},
    );
    final conditional = (obligationReport['conditional'] as List?)
            ?.whereType<Map>()
            .map((item) => ConditionalObligationSnapshot.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(growable: false) ??
        const <ConditionalObligationSnapshot>[];
    final vatReportJson = response['vat_report'];
    final inputVatReportJson = response['input_vat_report'];
    final vatReturnJson = response['vat_return'];
    final etimsJson = Map<String, dynamic>.from(
      ((obligationReport['etims'] as Map?) ?? const <String, dynamic>{}),
    );
    final etimsQueueJson = etimsJson['queue'];
    final totReturnJson = response['tot_return'];
    return TaxEntitySnapshot(
      id: entity['id'] as String? ?? '',
      legalForm: entity['legal_form'] as String? ?? 'other',
      displayLabel: entity['display_label'] as String? ?? '',
      kraPinSet: entity['kra_pin_set'] == true,
      kraPinLast4: entity['kra_pin_last4'] as String?,
      obligations: (entity['registered_tax_obligations'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      accountingPeriodStartMonth:
          (entity['accounting_period_start_month'] as num?)?.toInt() ?? 1,
      status: entity['status'] as String? ?? 'needs_review',
      etimsOnboardingStatus:
          entity['etims_onboarding_status'] as String? ?? 'not_started',
      etimsMethod: entity['etims_method'] as String?,
      outletReference: mapping['outlet_reference'] as String?,
      linkedShopCount: (threshold['linked_shop_count'] as num?)?.toInt() ?? 0,
      turnover: Money.fromMinor(
        (threshold['turnover_minor'] as num?)?.toInt() ?? 0,
      ),
      thresholdStatus: threshold['status'] as String?,
      rules: ((entity['rules'] as List?) ?? const [])
          .whereType<Map>()
          .map((rule) => TaxRuleSnapshot.fromJson(
                Map<String, dynamic>.from(rule),
              ))
          .toList(growable: false),
      totEstimate: totReport['estimate_minor'] == null
          ? null
          : Money.fromMinor((totReport['estimate_minor'] as num).toInt()),
      totDueDate: DateTime.tryParse(totReport['due_date'] as String? ?? ''),
      totStatus: totReport['status'] as String?,
      vatReport: vatReportJson is Map
          ? VatReportSnapshot.fromJson(Map<String, dynamic>.from(vatReportJson))
          : null,
      inputVatReport: inputVatReportJson is Map
          ? InputVatReportSnapshot.fromJson(
              Map<String, dynamic>.from(inputVatReportJson))
          : null,
      vatReturn: vatReturnJson is Map
          ? VatReturnSnapshot.fromJson(Map<String, dynamic>.from(vatReturnJson))
          : null,
      etimsQueue: etimsQueueJson is Map
          ? EtimsQueueSnapshot.fromJson(
              Map<String, dynamic>.from(etimsQueueJson))
          : null,
      totReturn: totReturnJson is Map
          ? TotReturnSnapshot.fromJson(Map<String, dynamic>.from(totReturnJson))
          : null,
      conditionalObligations: conditional,
    );
  }
}
