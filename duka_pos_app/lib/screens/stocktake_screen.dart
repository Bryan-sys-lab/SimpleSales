import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../services/app_state.dart';
import '../services/audit_actor.dart';
import '../models/audit_log.dart';
import '../utils/crypto_utils.dart';
import '../services/roles.dart';
import '../ui/dialogs/manager_approval_sheet.dart';
import '../profile/profile_navigation.dart';

/// Small, offline-first stocktake surface. The database owns the snapshot and
/// apply transaction; this screen only edits the operator's count entries.
class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({super.key});

  @override
  State<StocktakeScreen> createState() => _StocktakeScreenState();
}

class _StocktakeScreenState extends State<StocktakeScreen> {
  final _db = DatabaseHelper.instance;
  int? _countId;
  bool _blind = false;
  bool _freeze = false;
  bool _tankDip = false;
  String _scopeType = 'all';
  bool _busy = false;
  List<Map<String, dynamic>> _lines = const [];
  List<Map<String, dynamic>> _history = const [];

  @override
  void initState() {
    super.initState();
    _resume();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await _db.getStockCountHistory();
    if (mounted) setState(() => _history = history);
  }

  Future<void> _resume() async {
    final count = await _db.getInProgressStockCount();
    if (!mounted || count == null) return;
    setState(() {
      _countId = count['id'] as int;
      _blind = (count['blind'] as num? ?? 0) == 1;
      _freeze = (count['freeze'] as num? ?? 0) == 1;
      _scopeType = count['scope_type'] as String? ?? 'all';
      _tankDip = _scopeType == 'tanks';
    });
    await _loadLines();
  }

  Future<void> _start() async {
    final state = context.read<AppState>();
    if (!state.isOwnerSession &&
        state.permissionMode(PermissionKey.runStocktakeApply) ==
            PermissionMode.approval) {
      final approver = await showManagerApprovalSheet(
        context,
        purpose: 'Approve applying this stocktake',
      );
      if (!mounted || approver == null) return;
    }
    setState(() => _busy = true);
    final bool tankDip =
        _tankDip && state.shopProfile.navigation.showDrinkService;
    final id = await _db.startStockCount(
      uuid: generateUuid(),
      staffId: state.currentStaffId,
      staffName: state.currentStaffName ?? 'Unknown',
      blind: _blind,
      freeze: _freeze,
      name: tankDip ? 'Tank dip' : 'Stocktake',
      scopeType: tankDip ? 'tanks' : 'all',
      note: tankDip ? 'Next-day tank dip' : null,
    );
    if (!mounted) return;
    setState(() => _countId = id);
    await _loadLines();
  }

  Future<void> _loadLines() async {
    final id = _countId;
    if (id == null) return;
    final lines = await _db.getStockCountLines(id);
    if (mounted) setState(() => _lines = lines);
  }

  Future<void> _apply() async {
    final id = _countId;
    if (id == null || _lines.any((line) => line['counted_qty'] == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter every count before applying')),
      );
      return;
    }
    final state = context.read<AppState>();
    setState(() => _busy = true);
    await _db.applyStockCount(
      countId: id,
      staffId: state.currentStaffId,
      staffName: state.currentStaffName ?? 'Unknown',
    );
    await recordActionAudit(
      state,
      action: AuditAction.stockAdjusted,
      entity: AuditEntity.product,
      entityId: 'stock-count-$id',
      detail: _scopeType == 'tanks'
          ? 'tank dip applied'
          : 'physical stock count applied',
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _enterCount(Map<String, dynamic> line) async {
    final controller = TextEditingController(
      text: (line['counted_qty'] as num?)?.toString() ?? '',
    );
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(line['product_name'] as String),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Counted quantity'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !value.isFinite || value < 0) return;
    await _db.recordStockCountLine(
        lineId: line['id'] as int, countedQty: value);
    await _loadLines();
  }

  Future<void> _recount(Map<String, dynamic> line) async {
    await _db.clearStockCountLine(line['id'] as int);
    await _loadLines();
  }

  @override
  Widget build(BuildContext context) {
    final showTankDip =
        context.watch<AppState>().shopProfile.navigation.showDrinkService;
    final isTankDip = _scopeType == 'tanks' || _tankDip;
    return Scaffold(
      appBar: AppBar(title: Text(isTankDip ? 'Tank dip' : 'Stocktake')),
      body: _countId == null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(isTankDip
                      ? 'Record the measured tank level and apply only the variance.'
                      : 'Count the current stock and apply only the variances.'),
                  SwitchListTile(
                    title: Text('Blind count'),
                    subtitle: Text('Hide expected quantities while counting'),
                    value: _blind,
                    onChanged: (value) => setState(() => _blind = value),
                  ),
                  SwitchListTile(
                    title: Text('Freeze counted items'),
                    subtitle: Text('Block sales for items in this count'),
                    value: _freeze,
                    onChanged: (value) => setState(() => _freeze = value),
                  ),
                  if (showTankDip)
                    SwitchListTile(
                      title: const Text('Tank dip'),
                      subtitle: const Text(
                          'Count only tanks and record the physical dip variance'),
                      value: _tankDip,
                      onChanged: (value) => setState(() => _tankDip = value),
                    ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _start,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start stocktake'),
                  ),
                  if (_history.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('Recent stocktakes',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final count in _history)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title:
                            Text('${count['staff_name']} · ${count['status']}'),
                        subtitle: Text(count['completed_at'] as String? ??
                            count['started_at'] as String),
                      ),
                  ],
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final line in _lines)
                  ListTile(
                    title: Text(line['product_name'] as String),
                    subtitle: _blind
                        ? null
                        : Text(
                            'Expected ${(line['expected_qty'] as num).toStringAsFixed(2)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            (line['counted_qty'] as num?)?.toStringAsFixed(2) ??
                                '—'),
                        if (line['counted_qty'] != null)
                          IconButton(
                            tooltip: 'Request recount',
                            onPressed: () => _recount(line),
                            icon: const Icon(Icons.refresh),
                          ),
                      ],
                    ),
                    onTap: () => _enterCount(line),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _apply,
                  child: const Text('Apply stocktake'),
                ),
              ],
            ),
    );
  }
}
