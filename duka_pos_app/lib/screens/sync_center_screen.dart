import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/analytics.dart';
import '../services/app_state.dart';
import '../services/live_channel_service.dart';
import '../services/live_refresh_mixin.dart';
import '../services/roles.dart';
import '../services/backend_service.dart';
import '../services/auto_sync_service.dart';
import '../services/excel_service.dart';
import '../services/printer/printer_config.dart';
import '../services/etims/etims_service.dart';
import '../utils/money.dart';
import '../theme/app_colors.dart';

/// A compact owner/manager view of work that still needs reconciliation.
class SyncCenterScreen extends StatefulWidget {
  const SyncCenterScreen({super.key});

  @override
  State<SyncCenterScreen> createState() => _SyncCenterScreenState();
}

class _SyncCenterScreenState extends State<SyncCenterScreen>
    with LiveRefresh<SyncCenterScreen> {
  bool _loading = true;
  String? _error;
  AttentionSummary? _attention;
  int _unclaimed = 0;
  int _pendingPaymentPushes = 0;
  int _pendingPaymentClaims = 0;
  int _issuedEtims = 0;
  int _rejectedEtims = 0;
  int _backupRows = 0;
  DateTime? _lastBackup;
  bool _backupOverdue = true;
  bool _syncing = false;
  List<(Sale, Map<String, dynamic>)> _unverified = const [];
  List<PendingEtimsReceipt> _etims = const [];
  bool _cloudLinked = false;
  bool _identityVerified = false;
  Map<String, int> _unsynced = const <String, int>{};
  Map<String, int> _remoteOperational = const <String, int>{};
  List<Map<String, dynamic>> _conflicts = const <Map<String, dynamic>>[];
  PrinterConfig? _printer;
  bool _storageAvailable = false;

  @override
  Set<LiveReason> get liveReasons => const <LiveReason>{
        LiveReason.sales,
        LiveReason.stock,
        LiveReason.settings,
      };

  @override
  Future<void> reloadFromLive() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = DatabaseHelper.instance;
      final result = await Future.wait<Object?>([
        db.attentionSummary(),
        db.getPendingEtimsReceipts(limit: 100),
        db.getUnverifiedSales(limit: 100),
        db.countIncomingPayments(status: 'unclaimed'),
        db.countPendingPayments(),
        db.countPendingIncomingPaymentClaims(),
        db.countRejectedEtimsReceipts(),
        db.etimsStatusCounts(),
        db.countBackupLog(),
        ExcelService.lastBackupTime(),
        ExcelService.isBackupOverdue(),
        BackendService.isBackendLinked,
        BackendService.isIdentityVerified,
        PrinterConfig.load(),
        db.unsyncedOperationalCounts(),
        db.remoteOperationalCounts(),
        db.getOpenSyncConflicts(),
        _checkLocalStorage(),
      ]);
      if (!mounted) return;
      setState(() {
        _attention = result[0] as AttentionSummary;
        _etims = result[1] as List<PendingEtimsReceipt>;
        _unverified = result[2] as List<(Sale, Map<String, dynamic>)>;
        _unclaimed = result[3] as int;
        _pendingPaymentPushes = result[4] as int;
        _pendingPaymentClaims = result[5] as int;
        _rejectedEtims = result[6] as int;
        final etimsStatus = result[7] as Map<String, int>;
        _issuedEtims = etimsStatus['issued'] ?? 0;
        _backupRows = result[8] as int;
        _lastBackup = result[9] as DateTime?;
        _backupOverdue = result[10] as bool;
        _cloudLinked = result[11] as bool;
        _identityVerified = result[12] as bool;
        _printer = result[13] as PrinterConfig;
        _unsynced = result[14] as Map<String, int>;
        _remoteOperational = result[15] as Map<String, int>;
        _conflicts = result[16] as List<Map<String, dynamic>>;
        _storageAvailable = result[17] as bool;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Sync status could not be loaded.';
      });
    }
  }

  Future<bool> _checkLocalStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return await directory.exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> _retryEtims({required bool rejected}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final result = rejected
          ? await EtimsService().retryRejected()
          : await EtimsService().flushPending();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(EtimsService.describeResult(result))),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'KRA could not be reached. The receipts remain queued for the next connection.'),
      ));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await AutoSyncService.runNow(force: true);
      await _load();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _plainConflictReason(String? reason) {
    final value = reason?.trim() ?? '';
    if (value.isEmpty) return 'Another till used the stock first.';
    final lower = value.toLowerCase();
    if (lower.contains('stock') || lower.contains('quantity')) {
      return 'Another till used the stock first. Check the sale and stock count before deciding what to do.';
    }
    if (lower.contains('duplicate') || lower.contains('already')) {
      return 'This sale was already received by the server. It stays in the queue until it is confirmed.';
    }
    return value;
  }

  String _plainEtimsError(String? error) {
    final value = error?.trim() ?? '';
    if (value.isEmpty) return 'Waiting for a connection to KRA.';
    final lower = value.toLowerCase();
    if (lower.contains('timeout') ||
        lower.contains('socket') ||
        lower.contains('connection')) {
      return 'KRA could not be reached. It will retry when the connection returns.';
    }
    if (lower.contains('tin')) {
      return 'The shop TIN was not accepted. Check Tax settings before retrying.';
    }
    if (lower.contains('buyer') || lower.contains('pin')) {
      return 'The buyer details were not accepted. Check the saved buyer information.';
    }
    if (lower.contains('duplicate') || lower.contains('already')) {
      return 'KRA says this receipt was already submitted. Confirm the receipt number before retrying.';
    }
    return value;
  }

  Future<void> _reviewConflict(Map<String, dynamic> conflict) async {
    final uuid = conflict['uuid'] as String?;
    if (uuid == null || uuid.isEmpty) return;
    final resolution = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolve stock conflict'),
        content: Text(
          '${_plainConflictReason(conflict['reason'] as String?)}\n\n'
          'Choose how the manager wants this offline sale recorded. The sale is never deleted from the local audit ledger.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Leave open'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('void'),
            child: const Text('Void sale'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('accept_negative_stock'),
            child: const Text('Accept sale'),
          ),
        ],
      ),
    );
    if (resolution == null || !mounted) return;
    try {
      await BackendService.resolveSaleSyncConflict(
        conflict: conflict,
        resolution: resolution,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resolve conflict: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final allowed = state.isOwnerSession || state.role == ShopRole.manager;
    if (!allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sync Center')),
        body: const Center(child: Text('Only a manager can view Sync Center.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Center'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton.icon(
              onPressed: _loading || _syncing ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_sync_outlined),
              label: Text(_syncing ? 'Syncing' : 'Sync now'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _section(
                        context,
                        'Needs attention',
                        Icons.error_outline,
                        [
                          _status('eTIMS pending', _attention!.pendingEtims),
                          _status('eTIMS rejected', _attention!.rejectedEtims),
                          _status('eTIMS issued', _issuedEtims),
                          if (_rejectedEtims > 0)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: const Text('Rejected receipts to retry'),
                              trailing: TextButton(
                                onPressed: _syncing
                                    ? null
                                    : () => _retryEtims(rejected: true),
                                child: const Text('Retry'),
                              ),
                            ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Unverified payments'),
                            trailing: _attention!.unverifiedPayments == 0
                                ? const Text('0')
                                : TextButton(
                                    onPressed: () => context
                                        .push('/settings/incoming-payments'),
                                    child: Text(
                                        'Open (${_attention!.unverifiedPayments})'),
                                  ),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Unclaimed M-Pesa'),
                            trailing: _unclaimed == 0
                                ? const Text('0')
                                : TextButton(
                                    onPressed: () => context
                                        .push('/settings/incoming-payments'),
                                    child: Text('Open ($_unclaimed)'),
                                  ),
                          ),
                          _status('eTIMS queue rows', _etims.length),
                          _status(
                              'M-Pesa prompts waiting', _pendingPaymentPushes),
                          _status(
                              'M-Pesa claims waiting', _pendingPaymentClaims),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _section(
                        context,
                        'Local records',
                        Icons.inventory_2_outlined,
                        [
                          _status('Backup log entries', _backupRows),
                          _status('Backup overdue', _backupOverdue ? 1 : 0),
                          if (_lastBackup != null)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: const Text('Last local backup'),
                              trailing: Text(_lastBackup!.toLocal().toString()),
                            ),
                          _status('Unverified sales', _unverified.length),
                          _status(
                            'Cloud link',
                            _cloudLinked ? 1 : 0,
                          ),
                          _status(
                            'Cloud identity verified',
                            _identityVerified ? 1 : 0,
                          ),
                          _status(
                              'Sales waiting to sync', _unsynced['sales'] ?? 0),
                          _status(
                              'Sales needing stock review', _conflicts.length),
                          _status(
                            'Cash control waiting to sync',
                            (_unsynced['expenses'] ?? 0) +
                                (_unsynced['till_movements'] ?? 0) +
                                (_unsynced['drawer_events'] ?? 0),
                          ),
                          _status(
                            'Stock/returns waiting to sync',
                            (_unsynced['stock_receipts'] ?? 0) +
                                (_unsynced['sale_returns'] ?? 0) +
                                (_unsynced['stock_movements'] ?? 0),
                          ),
                          _status('Serving setup waiting to sync',
                              _unsynced['shot_cups'] ?? 0),
                          _status(
                            'Remote operational rows mirrored',
                            _remoteOperational.values
                                .fold<int>(0, (sum, count) => sum + count),
                          ),
                          _status(
                            'Printer',
                            _printer?.isConfigured == true ? 1 : 0,
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Local storage access'),
                            trailing: Text(
                              _storageAvailable ? 'Available' : 'Unavailable',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _storageAvailable
                                    ? AppColors.of(context).success
                                    : AppColors.of(context).danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_conflicts.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Sales needing review',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                const Text(
                                    'These offline sales could not reserve stock after another till sold the last units. They remain queued and are not silently discarded.'),
                                for (final conflict in _conflicts)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                        Icons.warning_amber_outlined),
                                    title: Text(
                                        'Sale ${conflict['local_id'] ?? ''}'),
                                    subtitle: Text(_plainConflictReason(
                                        conflict['reason'] as String?)),
                                    trailing: TextButton(
                                      onPressed: () =>
                                          _reviewConflict(conflict),
                                      child: const Text('Review'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_unverified.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Payments to reconcile',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 8),
                                for (final (sale, row) in _unverified.take(5))
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(formatMoney(sale.total)),
                                    subtitle: Text(
                                        row['created_at'] as String? ?? ''),
                                    trailing: const Icon(
                                        Icons.warning_amber_outlined),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_etims.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('eTIMS queue',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: TextButton.icon(
                                    onPressed: _syncing
                                        ? null
                                        : () => _retryEtims(rejected: false),
                                    icon: const Icon(Icons.sync),
                                    label: const Text('Retry queued receipts'),
                                  ),
                                ),
                                for (final receipt in _etims.take(5))
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(receipt.receiptNumber),
                                    subtitle: Text(
                                        '${receipt.documentType == 'credit_note' ? 'Credit note' : 'Invoice'} · ${receipt.attempts} attempt(s) · ${_plainEtimsError(receipt.lastError)}'),
                                    trailing:
                                        const Icon(Icons.receipt_long_outlined),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _section(BuildContext context, String title, IconData icon,
          List<Widget> children) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(title)
              ]),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );

  Widget _status(String label, int count) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label),
        trailing:
            Text('$count', style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}
