import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../data/local/database/shop_file_reader.dart';
import '../db/database_helper.dart';
import '../models/models.dart';
import '../profile/shop_profile.dart';
import '../services/backend_service.dart';
import '../services/app_state.dart';
import '../services/cross_shop_activity.dart';
import '../services/cross_shop_activity_reader.dart';
import '../services/roles.dart';
import '../services/session_refresh_mixin.dart';
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

class _CrossShopActivityScreenState extends State<CrossShopActivityScreen>
    with SessionRefresh<CrossShopActivityScreen> {
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

  /// Paging state for the two sources. They are separate because their cursors
  /// are different formats: handing the backend's cursor to the local reader
  /// (or the reverse) restarted it from the newest row, so "Load more" repeated
  /// the first page.
  String? _nextCursor;
  String? _remoteCursor;

  /// Shops on this device whose file could not be read on the last load.
  List<String> _unreadable = const <String>[];

  @override
  void clearForSession() {
    _shops = const <LocalShop>[];
    _events = const <CrossShopActivity>[];
    _nextCursor = null;
    _remoteCursor = null;
    _unreadable = const <String>[];
    _failed = false;
    _remoteUnavailable = false;
    _loading = true;
  }

  @override
  Future<void> reloadFromSession() => _load();

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
        _remoteCursor = null;
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
      var remoteCursor = append ? _remoteCursor : null;
      var remoteUnavailable = _remoteUnavailable;
      // The backend is asked on the first page, and again on later pages only
      // while it still has a cursor to continue from.
      if (!append || remoteCursor != null) {
        try {
          final remote = await BackendService.crossShopActivity(
            from: _from,
            to: _to,
            profile: _profile?.wireValue,
            payment: _payment,
            type: _type,
            status: _status,
            cursor: remoteCursor,
          );
          remoteCursor = remote.nextCursor;
          events.addAll(remote.events.map((event) => event.asRemote()));
        } catch (_) {
          remoteUnavailable = true;
          remoteCursor = null;
        }
      }
      events = CrossShopActivityReader.withoutDuplicates(events);
      events.sort(CrossShopActivityReader.compareNewestFirst);
      if (!mounted || generation != _generation) return;
      setState(() {
        _shops = shops;
        _events = events;
        _nextCursor = nextCursor;
        _remoteCursor = remoteCursor;
        _unreadable = append ? _unreadable : local.unreadableShops;
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

  /// The last DAY the range covers. A range chosen on the picker ends at the
  /// start of the next day (exclusive), so the day shown is the one before; the
  /// default range ends at "now", which is already on its last day. Subtracting
  /// a day from that one labelled the range as ending yesterday.
  DateTime get _lastDayShown {
    final DateTime to = _to.toLocal();
    final bool endsAtMidnight =
        to.hour == 0 && to.minute == 0 && to.second == 0 && to.millisecond == 0;
    return endsAtMidnight ? to.subtract(const Duration(days: 1)) : to;
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

  /// Opens the record an activity row is about, WITHOUT moving the till.
  ///
  /// It used to switch the open workspace to the row's shop and never switch
  /// back: tapping a row left the whole app on a different shop from the one the
  /// session, the shop name and the permissions belong to. A row from another
  /// shop is read from that shop's own file instead, and anything that would
  /// WRITE (a return) is offered only for the shop that is actually open.
  Future<void> _openSource(CrossShopActivity event) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Which shop on THIS device holds the record, if any. A backend row names a
    // tenant, not a workspace; its `workspaceKey` is only a copy of the tenant
    // id, and used as a workspace key it pointed at a shop that does not exist.
    final String? localShop = event.isRemote
        ? await WorkspaceService.workspaceForTenant(event.tenantId)
        : (event.workspaceKey.isEmpty ? null : event.workspaceKey);
    if (!mounted) return;
    final String openShop = DatabaseHelper.instance.currentWorkspaceKey;

    if (event.sourceType == 'sale') {
      final int? localId = int.tryParse(event.sourceId);
      if (!event.isRemote && localId != null && localShop != null) {
        final bool isOpenShop = localShop == openShop;
        Sale? sale;
        try {
          sale = isOpenShop
              ? await DatabaseHelper.instance.getSaleById(localId)
              : await ShopFileReader.saleById(localShop, localId);
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.crossShopCouldNotLoadSale)),
          );
          return;
        }
        if (!mounted) return;
        if (sale == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.crossShopSaleNoLongerOnTill)),
          );
          return;
        }
        final appState = context.read<AppState>();
        await showSaleDetails(
          context,
          sale: sale,
          canSeeSellers: appState.canManageStock,
          // A return is written to the OPEN shop's database, so it is offered
          // only there.
          canProcessReturn:
              isOpenShop && appState.hasPermission(PermissionKey.processReturn),
          shopName: event.shopName,
        );
        return;
      }
      try {
        final remote = await BackendService.remoteSaleDetails(
          event.sourceId,
          tenantId: event.tenantId,
        );
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('${event.shopName} sale'),
            content: SingleChildScrollView(
              child: Text(_describeRemoteSale(remote)),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.crossShopClose),
              ),
            ],
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.crossShopCouldNotLoadSale)),
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
            child: Text(l10n.crossShopClose),
          ),
        ],
      ),
    );
  }

  /// A backend sale as readable lines. It used to show `Map.toString()`.
  static String _describeRemoteSale(Map<String, dynamic> sale) {
    String label(String key) {
      final spaced = key.replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
      final words = spaced.replaceAll('_', ' ').trim();
      return words.isEmpty ? key : words[0].toUpperCase() + words.substring(1);
    }

    final lines = <String>[];
    sale.forEach((key, value) {
      if (value == null) return;
      if (value is List) {
        lines.add('${label(key)}:');
        for (final item in value) {
          if (item is Map) {
            final name = item['productName'] ?? item['product_name'] ?? item['name'];
            final qty = item['qty'] ?? item['quantity'];
            final total = item['total'] ?? item['lineTotal'];
            lines.add('  • ${[
              if (name != null) '$name',
              if (qty != null) '× $qty',
              if (total != null) '— $total',
            ].join(' ')}');
          } else {
            lines.add('  • $item');
          }
        }
      } else if (value is Map) {
        return;
      } else {
        lines.add('${label(key)}: $value');
      }
    });
    return lines.isEmpty ? 'No details were returned.' : lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).crossShopAllShopsActivity),
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
                  '${_from.toLocal().toString().substring(0, 10)} – ${_lastDayShown.toString().substring(0, 10)}'),
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
            if (_unreadable.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Could not read: ${_unreadable.join(', ')}. '
                  'Their activity is not shown.',
                ),
              ),
            if (_remoteUnavailable)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                    'Showing local activity. Some linked shops may be offline or stale.'),
              ),
            if (_failed)
              Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(AppLocalizations.of(context).crossShopCouldNotReadActivity)),
            if (!_loading && !_failed && _events.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: Text('No matching activity.')),
              ),
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
            if (!_loading && (_nextCursor != null || _remoteCursor != null))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton(
                  onPressed: () => _load(append: true),
                  child: Text(AppLocalizations.of(context).crossShopLoadMoreActivity),
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
