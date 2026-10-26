import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../profile/shop_profile.dart';
import '../services/backend_service.dart';
import '../services/app_state.dart';
import '../services/cross_shop_activity.dart';
import '../services/cross_shop_activity_reader.dart';
import '../services/roles.dart';
import '../services/workspace_service.dart';
import '../theme/app_colors.dart';
import '../utils/money.dart';
import '../widgets/sale_details_sheet.dart';

/// The owner-facing normalized feed across all authorized shops.
class CrossShopActivityScreen extends StatefulWidget {
  const CrossShopActivityScreen({super.key});

  @override
  State<CrossShopActivityScreen> createState() =>
      _CrossShopActivityScreenState();
}

class _CrossShopActivityScreenState extends State<CrossShopActivityScreen> {
  late DateTime _from;
  late DateTime _to;
  String? _shop;
  ShopProfile? _profile;
  String? _payment;
  String? _type;
  String? _status;
  List<LocalShop> _shops = const <LocalShop>[];
  List<CrossShopActivity> _events = const <CrossShopActivity>[];
  bool _loading = true;
  bool _failed = false;
  bool _remoteUnavailable = false;
  int _generation = 0;
  String? _nextCursor;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 30));
    _to = now;
    _load();
  }

  Future<void> _load({bool append = false}) async {
    final int generation = ++_generation;
    setState(() {
      _loading = true;
      if (!append) {
        _failed = false;
        _remoteUnavailable = false;
        _nextCursor = null;
      }
    });
    final filters = CrossShopActivityFilters(
      from: _from,
      to: _to,
      workspaceKey: _shop,
      profile: _profile,
      paymentMethod: _payment,
      type: _type,
      status: _status,
      cursor: append ? _nextCursor : null,
    );
    try {
      final shops = await WorkspaceServiceShops.localShops();
      final local = await CrossShopActivityReader.readLocal(filters);
      var events = <CrossShopActivity>[
        ...(append ? _events : const <CrossShopActivity>[]),
        ...local.events,
      ];
      var nextCursor = local.nextCursor;
      var remoteUnavailable = _remoteUnavailable;
      if (!append) {
        try {
          final remote = await BackendService.crossShopActivity(
            from: _from,
            to: _to,
            profile: _profile?.wireValue,
            payment: _payment,
            type: _type,
            status: _status,
            cursor: append ? _nextCursor : null,
          );
          nextCursor ??= remote.nextCursor;
          final known = events.map((event) => event.eventId).toSet();
          events.addAll(
              remote.events.where((event) => !known.contains(event.eventId)));
        } catch (_) {
          // Offline is valid, but must be visible as incomplete/stale data.
          remoteUnavailable = true;
        }
      }
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted || generation != _generation) return;
      setState(() {
        _shops = shops;
        _events = events;
        _nextCursor = nextCursor;
        _remoteUnavailable = remoteUnavailable;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _change<T>(void Function() change) {
    setState(change);
    _load();
  }

  Future<void> _chooseDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range == null) return;
    _change(() {
      _from = DateTime(range.start.year, range.start.month, range.start.day);
      _to = DateTime(range.end.year, range.end.month, range.end.day)
          .add(const Duration(days: 1));
    });
  }

  Future<void> _openSource(CrossShopActivity event) async {
    final workspace = event.workspaceKey.isNotEmpty
        ? event.workspaceKey
        : await WorkspaceService.workspaceForTenant(event.tenantId);
    if (workspace != null && workspace.isNotEmpty) {
      await DatabaseHelper.instance.switchWorkspace(workspace);
    }
    if (!mounted) return;
    if (event.sourceType == 'sale') {
      final localId = int.tryParse(event.sourceId);
      if (localId != null && !event.isRemote) {
        final sale = await DatabaseHelper.instance.getSaleById(localId);
        if (!mounted) return;
        if (sale == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('This sale is no longer on this till.')),
          );
          return;
        }
        final appState = context.read<AppState>();
        await showSaleDetails(
          context,
          sale: sale,
          canSeeSellers: appState.canManageStock,
          canProcessReturn: appState.hasPermission(PermissionKey.processReturn),
          shopName: event.shopName,
        );
        return;
      }
      try {
        final remote = await BackendService.remoteSaleDetails(event.sourceId);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('${event.shopName} sale'),
            content: SingleChildScrollView(child: Text(remote.toString())),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load this sale.')),
        );
      }
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${event.shopName} ${event.type}'),
        content: Text(
          '${event.sourceType} ${event.sourceId}\n'
          '${event.status}\n\n${event.detail ?? 'Source record available in this shop.'}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('All shops activity'),
        actions: <Widget>[
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: _chooseDateRange,
              icon: const Icon(Icons.date_range),
              label: Text(
                  '${_from.toLocal().toString().substring(0, 10)} – ${_to.subtract(const Duration(days: 1)).toLocal().toString().substring(0, 10)}'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _select<String>(
                  label: 'Shop',
                  value: _shop,
                  items: <String?>[
                    null,
                    ..._shops.map((shop) => shop.workspaceKey)
                  ],
                  text: (value) => value == null
                      ? 'All shops'
                      : _shops
                          .firstWhere((shop) => shop.workspaceKey == value,
                              orElse: () => const LocalShop(
                                  workspaceKey: '', shopName: 'Shop'))
                          .shopName,
                  onChanged: (value) => _change(() => _shop = value),
                ),
                _select<ShopProfile>(
                  label: 'Profile',
                  value: _profile,
                  items: <ShopProfile?>[null, ...ShopProfile.values],
                  text: (value) => value?.displayName ?? 'All profiles',
                  onChanged: (value) => _change(() => _profile = value),
                ),
                _select<String>(
                  label: 'Payment',
                  value: _payment,
                  items: const <String?>[null, 'cash', 'mpesa', 'card', 'bank'],
                  text: (value) => value ?? 'All payments',
                  onChanged: (value) => _change(() => _payment = value),
                ),
                _select<String>(
                  label: 'Type',
                  value: _type,
                  items: const <String?>[null, 'sale', 'activity'],
                  text: (value) => value ?? 'All types',
                  onChanged: (value) => _change(() => _type = value),
                ),
                _select<String>(
                  label: 'Status',
                  value: _status,
                  items: const <String?>[
                    null,
                    'completed',
                    'unverified',
                    'recorded'
                  ],
                  text: (value) => value ?? 'All statuses',
                  onChanged: (value) => _change(() => _status = value),
                ),
              ],
            ),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator()),
            if (_remoteUnavailable)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                    'Showing local activity. Some linked shops may be offline or stale.'),
              ),
            if (_failed)
              const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text('Could not read shop activity. Pull to retry.')),
            if (!_loading && !_failed && _events.isEmpty)
              const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(child: Text('No matching activity.'))),
            ..._events.map((event) => Card(
                  color: colors.surface,
                  child: ListTile(
                    onTap: () => _openSource(event),
                    title: Text('${event.shopName} · ${event.type}'),
                    subtitle: Text(
                        '${event.status} · ${event.actor ?? 'Unknown'} · ${event.createdAt.toLocal().toString().substring(0, 16)}${event.detail == null ? '' : '\n${event.detail}'}'),
                    isThreeLine: event.detail != null,
                    trailing: event.amount.isZero
                        ? null
                        : Text(formatMoney(event.amount)),
                  ),
                )),
            if (!_loading && _nextCursor != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton(
                  onPressed: () => _load(append: true),
                  child: const Text('Load more activity'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _select<T>({
    required String label,
    required T? value,
    required List<T?> items,
    required String Function(T?) text,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<T?>(
        initialValue: value,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        items: items
            .map((item) =>
                DropdownMenuItem<T?>(value: item, child: Text(text(item))))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
