import 'backend_service.dart';

/// The owner-controlled server copy described by the release-1 sync contract.
///
/// This service is deliberately an allowlist of operational/business records:
/// catalogue, staff, sales, books, stock, customer credit, and encrypted
/// backup. It has no commercial-intelligence contribution method and does not
/// send a second, inferred copy of these records to an analytics pipeline.
/// Keeping this boundary named makes a future commercial contributor harder to
/// accidentally wire into the owner backup path.
class OwnerBusinessSyncService {
  const OwnerBusinessSyncService._();

  static const List<String> ownerBusinessDomains = <String>[
    'catalogue',
    'staff',
    'sales',
    'financial_evidence',
    'customer_credit',
    'laybys',
    'exchanges',
    'shifts',
    'stock_cups',
    'returns',
    'receipts',
    'reordering',
    'stock_movements',
    'expenses_and_till_movements',
    'drawer_events',
    'operational_records',
    'incoming_payments',
    'encrypted_full_backup',
  ];

  static Future<OwnerBusinessSyncReport> run() async {
    final completed = <String>[];
    final failed = <OwnerBusinessSyncFailure>[];

    Future<void> attempt(String domain, Future<void> Function() action) async {
      try {
        await action();
        completed.add(domain);
      } catch (error) {
        failed.add(OwnerBusinessSyncFailure(domain, error.toString()));
      }
    }

    await attempt('catalogue', () async {
      await BackendService.syncProductsToBackend();
      await BackendService.pullProductsFromBackend();
    });
    await attempt('staff', () async {
      await BackendService.syncStaffToBackend();
      await BackendService.pullStaffFromBackend();
    });
    await attempt('sales', () async {
      await BackendService.syncSalesToBackend();
    });
    await attempt(
        'financial_evidence', BackendService.syncFinancialEvidenceToBackend);
    await attempt('customer_credit', () async {
      await BackendService.syncCustomersAndCreditToBackend();
      await BackendService.pullCustomersAndCreditFromBackend();
    });
    await attempt('laybys', BackendService.syncLaybysToBackend);
    await attempt('exchanges', BackendService.syncExchangesToBackend);
    await attempt('shifts', BackendService.syncShiftsToBackend);
    await attempt('stock_cups', () async {
      await BackendService.syncShotCupsToBackend();
      await BackendService.pullShotCupsFromBackend();
    });
    await attempt('returns', BackendService.syncReturnsToBackend);
    await attempt('receipts', BackendService.syncReceiptsToBackend);
    await attempt('reordering', BackendService.syncReorderingToBackend);
    await attempt(
        'stock_movements', BackendService.syncStockMovementsToBackend);
    await attempt('expenses_and_till_movements',
        BackendService.syncExpensesAndTillMovementsToBackend);
    await attempt('drawer_events', BackendService.syncDrawerEventsToBackend);
    await attempt('operational_records',
        BackendService.pullOperationalRecordsFromBackend);
    await attempt('incoming_payments', () async {
      await BackendService.syncIncomingMpesaClaims();
      await BackendService.pullIncomingMpesaToLocal();
    });
    await attempt(
        'encrypted_full_backup', BackendService.syncFullBackupToBackend);

    return OwnerBusinessSyncReport(
      completed: List<String>.unmodifiable(completed),
      failed: List<OwnerBusinessSyncFailure>.unmodifiable(failed),
    );
  }
}

class OwnerBusinessSyncFailure {
  const OwnerBusinessSyncFailure(this.domain, this.message);

  final String domain;
  final String message;
}

class OwnerBusinessSyncReport {
  const OwnerBusinessSyncReport(
      {required this.completed, required this.failed});

  final List<String> completed;
  final List<OwnerBusinessSyncFailure> failed;

  bool get succeeded => failed.isEmpty;
}
