import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import '../services/excel_service.dart';
import '../widgets/backup_reminder_banner.dart';
import '../utils/money.dart';
import '../services/app_state.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Sale> _todaySales = [];
  List<Product> _products = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final since = DateTime.now()
          .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
      final state = context.read<AppState>();
      final sales = await DatabaseHelper.instance.getSales(
        since: since,
        staffName:
            state.currentRole == 'cashier' ? state.currentStaffName : null,
        // Dashboard aggregates per sale only; skip hydrating line items.
        withItems: false,
      );
      final products = await DatabaseHelper.instance.getProducts();
      if (!mounted) return;
      setState(() {
        _todaySales = sales;
        _products = products;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn’t load today’s dashboard data.';
      });
    }
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
    // Summing integer cents, so a day's takings reconcile exactly.
    final total = sumMoney(_todaySales.map((s) => s.total));
    final profit = sumMoney(_todaySales.map((s) => s.profit));
    final low = _products.where((p) => p.isLow).toList()
      ..sort((a, b) => a.stockQty.compareTo(b.stockQty));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          BackupReminderBanner(onBackupNow: () async {
            final file = await ExcelService().exportEncryptedInventory();
            await ExcelService().shareFile(file);
          }),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              _kpi(context, 'Sales today', formatMoney(total)),
              _kpi(context, 'Profit today', formatMoney(profit)),
              _kpi(context, 'Transactions', '${_todaySales.length}'),
              _kpi(context, 'Low stock items', '${low.length}',
                  warn: low.isNotEmpty),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(
              header: true,
              child: Text('Low stock',
                  style: Theme.of(context).textTheme.titleMedium)),
          const SizedBox(height: 8),
          if (low.isEmpty)
            const Text('All stocked up.')
          else
            Card(
              child: Column(
                  children: low
                      .map((p) => ListTile(
                            title: Text(p.name),
                            trailing: Text('${p.stockQty} left',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                          ))
                      .toList()),
            ),
        ],
      ),
    );
  }

  Widget _kpi(BuildContext context, String label, String value,
          {bool warn = false}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color:
                          warn ? Theme.of(context).colorScheme.error : null)),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}
