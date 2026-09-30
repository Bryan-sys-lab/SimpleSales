import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/excel_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _money =
      NumberFormat.currency(locale: 'en_KE', symbol: 'KSh ', decimalDigits: 0);
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
              state.currentRole == 'cashier' ? state.currentStaffName : null);
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
    final total = mine.fold<double>(0, (a, s) => a + s.total);
    final profit = mine.fold<double>(0, (a, s) => a + s.profit);
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
                    Text('Total sales: ${_money.format(total)}'),
                    Text('Profit: ${_money.format(profit)}'),
                    const Divider(),
                    Text('Cash expected in till: ${_money.format(total)}',
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
    final byStaff = <String, Map<String, double>>{};
    for (final s in _sales) {
      final m = byStaff.putIfAbsent(
          s.staffName, () => {'n': 0, 'total': 0, 'profit': 0});
      m['n'] = m['n']! + 1;
      m['total'] = m['total']! + s.total;
      m['profit'] = m['profit']! + s.profit;
    }
    final staffRows = byStaff.entries.toList()
      ..sort((a, b) => b.value['total']!.compareTo(a.value['total']!));

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
                                Text('${e.value['n']!.toInt()} transactions'),
                            trailing: Text(_money.format(e.value['total']!)),
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
                                '${s.staffName} · ${_money.format(s.total)}'),
                            subtitle: Text(
                                '${DateFormat('MMM d, h:mm a').format(DateTime.parse(s.createdAt))} · ${s.paymentMethod}${s.changeGiven > 0 ? ' · change ${_money.format(s.changeGiven)}' : ''}'),
                          ))
                      .toList())),
        ],
      ),
    );
  }
}
