import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/excel_service.dart';
import '../utils/money.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _excel = ExcelService();
  List<Sale> _sales = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = context.read<AppState>();
      final sales = await DatabaseHelper.instance.getSales(
        staffName:
            state.currentRole == 'cashier' ? state.currentStaffName : null,
        // Reports aggregates per sale only; skip hydrating line items.
        withItems: false,
      );
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn’t load sales reports.';
      });
    }
  }

  Future<void> _showShiftSummary() async {
    final staffName = context.read<AppState>().currentStaffName!;
    final today = DateTime.now();
    final mine = _sales
        .where((s) =>
            s.staffName == staffName &&
            DateTime.parse(s.createdAt).day == today.day &&
            DateTime.parse(s.createdAt).month == today.month &&
            DateTime.parse(s.createdAt).year == today.year)
        .toList();
    final total = sumMoney(mine.map((s) => s.total));
    final profit = sumMoney(mine.map((s) => s.profit));
    if (!mounted) return;
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Shift summary'),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cashier: $staffName'),
                    Text('Transactions: ${mine.length}'),
                    Text('Total sales: ${formatMoney(total)}'),
                    Text('Profit: ${formatMoney(profit)}'),
                    const Divider(),
                    Text('Cash expected in till: ${formatMoney(total)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ],
            ));
  }

  Future<void> _exportSales() async {
    final file = await _excel.exportEncryptedSales();
    await _excel.shareFile(file);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ]),
      ));
    }
    final byStaff = <String, Map<String, Object>>{};
    for (final s in _sales) {
      final m = byStaff.putIfAbsent(s.staffName, () => {
            'n': 0,
            'total': Money.zero,
            'profit': Money.zero,
          });
      m['n'] = (m['n']! as int) + 1;
      // Money in the accumulator, not a raw double: per-staff takings then sum
      // to the same figure as the day total, with no rounding to reconcile.
      m['total'] = (m['total']! as Money) + s.total;
      m['profit'] = (m['profit']! as Money) + s.profit;
    }
    final staffRows = byStaff.entries.toList()
      ..sort((a, b) =>
          (b.value['total']! as Money).compareTo(a.value['total']! as Money));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(
                child: FilledButton.icon(
                    onPressed: _showShiftSummary,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('My shift today'))),
            const SizedBox(width: 8),
            OutlinedButton.icon(
                onPressed: _exportSales,
                icon: const Icon(Icons.ios_share),
                label: const Text('Export')),
          ]),
          const SizedBox(height: 20),
          Text('Sales by staff',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
              child: Column(
                  children: staffRows
                      .map((e) => ListTile(
                            title: Text(e.key),
                            subtitle:
                                Text('${e.value['n']! as int} transactions'),
                            trailing: Text(formatMoney(e.value['total']! as Money)),
                          ))
                      .toList())),
          const SizedBox(height: 20),
          Text('Recent sales', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
              child: Column(
                  children: _sales
                      .take(50)
                      .map((s) => ListTile(
                            title: Text(
                                '${s.staffName} · ${formatMoney(s.total)}'),
                            subtitle: Text(
                                '${DateFormat('MMM d, h:mm a').format(DateTime.parse(s.createdAt))} · ${s.paymentMethod}${!s.changeGiven.isNegative ? ' · change ${formatMoney(s.changeGiven)}' : ''}'),
                          ))
                      .toList())),
        ],
      ),
    );
  }
}
