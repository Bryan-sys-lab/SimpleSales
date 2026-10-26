import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/incoming_payment.dart';
import '../services/app_state.dart';
import '../services/backend_service.dart';
import '../services/live_channel_service.dart';
import '../services/live_refresh_mixin.dart';
import '../services/roles.dart';
import '../utils/money.dart';

class IncomingPaymentsScreen extends StatefulWidget {
  const IncomingPaymentsScreen({super.key});

  @override
  State<IncomingPaymentsScreen> createState() => _IncomingPaymentsScreenState();
}

class _IncomingPaymentsScreenState extends State<IncomingPaymentsScreen>
    with SingleTickerProviderStateMixin, LiveRefresh<IncomingPaymentsScreen> {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  bool _loading = true;
  String? _error;
  List<IncomingPayment> _payments = const <IncomingPayment>[];
  int _unclaimedCount = 0;

  @override
  Set<LiveReason> get liveReasons => <LiveReason>{};

  @override
  Future<void> reloadFromLive() => _load(announce: true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load({bool announce = false}) async {
    try {
      final db = DatabaseHelper.instance;
      final local = await db.getIncomingPayments();
      if (await BackendService.isBackendLinked) {
        try {
          // Pull all visible states so a second till shows the same claim and
          // ignore history, not only the currently actionable queue.
          await BackendService.pullIncomingMpesaToLocal();
        } catch (_) {
          // Offline is a valid state: keep showing the last cached list.
        }
      }
      final payments = await db.getIncomingPayments();
      if (!mounted) return;
      final nextUnclaimed =
          payments.where((payment) => payment.status == 'unclaimed').length;
      final received = announce && nextUnclaimed > _unclaimedCount;
      setState(() {
        _payments = payments.isEmpty ? local : payments;
        _unclaimedCount = nextUnclaimed;
        _loading = false;
        _error = null;
      });
      if (received && mounted) {
        final l10n = AppLocalizations.of(context);
        SystemSound.play(SystemSoundType.alert);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.incomingPaymentsNewNotice),
        ));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context).incomingPaymentsLoadFailed;
      });
    }
  }

  Future<void> _ignore(IncomingPayment payment) async {
    final l10n = AppLocalizations.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(l10n.incomingPaymentsSetAsideTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.incomingPaymentsReason),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.actionCancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: Text(l10n.actionSave)),
          ],
        );
      },
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await BackendService.ignoreIncomingMpesa(
          remoteId: payment.remoteId, reason: reason);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.incomingPaymentsSetAsideFailed)));
      }
    }
  }

  List<IncomingPayment> _forStatus(String status) =>
      _payments.where((payment) => payment.status == status).toList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<AppState>();
    final isManager = state.isOwnerSession || state.role == ShopRole.manager;
    if (!isManager) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.incomingPaymentsTitle)),
        body: Center(child: Text(l10n.incomingPaymentsManagerOnly)),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.incomingPaymentsTitle),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: l10n.incomingPaymentsUnclaimed),
            Tab(text: l10n.incomingPaymentsClaimed),
            Tab(text: l10n.incomingPaymentsIgnored),
            Tab(text: l10n.incomingPaymentsDisputed),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _list(_forStatus('unclaimed'), canIgnore: true),
                    _list(_forStatus('claimed')),
                    _list(_forStatus('ignored')),
                    _list(_forStatus('disputed')),
                  ],
                ),
    );
  }

  Widget _list(List<IncomingPayment> payments, {bool canIgnore = false}) {
    final l10n = AppLocalizations.of(context);
    if (payments.isEmpty) {
      return Center(child: Text(l10n.incomingPaymentsEmpty));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: payments.length,
        itemBuilder: (context, index) {
          final payment = payments[index];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(formatMoney(payment.amount)),
              subtitle:
                  Text('${payment.payerMasked}\n${payment.transactionId}'),
              isThreeLine: true,
              trailing: canIgnore
                  ? IconButton(
                      tooltip: 'Set aside',
                      onPressed: () => _ignore(payment),
                      icon: const Icon(Icons.visibility_off_outlined),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}
