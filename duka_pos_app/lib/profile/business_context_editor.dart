import 'package:material_ui/material_ui.dart';

import '../db/database_helper.dart';
import 'business_context.dart';
import 'kesic_reference_2020.dart';
import 'shop_profile.dart';

const _counties = <String>[
  'Mombasa',
  'Kwale',
  'Kilifi',
  'Tana River',
  'Lamu',
  'Taita-Taveta',
  'Garissa',
  'Wajir',
  'Mandera',
  'Marsabit',
  'Isiolo',
  'Meru',
  'Tharaka-Nithi',
  'Embu',
  'Kitui',
  'Machakos',
  'Makueni',
  'Nyandarua',
  'Nyeri',
  'Kirinyaga',
  "Murang'a",
  'Kiambu',
  'Turkana',
  'West Pokot',
  'Samburu',
  'Trans Nzoia',
  'Uasin Gishu',
  'Elgeyo-Marakwet',
  'Nandi',
  'Baringo',
  'Laikipia',
  'Nakuru',
  'Narok',
  'Kajiado',
  'Kericho',
  'Bomet',
  'Kakamega',
  'Vihiga',
  'Bungoma',
  'Busia',
  'Siaya',
  'Kisumu',
  'Homa Bay',
  'Migori',
  'Kisii',
  'Nyamira',
  'Nairobi City',
];

const _operatorLabels = <String, String>{
  'producer': 'Producer',
  'manufacturer': 'Manufacturer',
  'importer': 'Importer',
  'distributor': 'Distributor',
  'wholesaler': 'Wholesaler',
  'retailer': 'Retailer',
  'service_provider': 'Service provider',
  'mixed': 'Mixed activity',
  'other': 'Other',
};
const _channelLabels = <String, String>{
  'physical_shop': 'Physical shop',
  'market_stall': 'Market stall',
  'mobile_route': 'Mobile route',
  'online_store': 'Online store',
  'social_commerce': 'Social commerce',
  'wholesale': 'Wholesale',
  'delivery': 'Delivery',
  'other': 'Other',
};
const _settlementLabels = <String, String>{
  'unknown': 'Not sure yet',
  'prefer_not_to_say': 'Prefer not to say',
  'urban': 'Urban',
  'peri_urban': 'Peri-urban',
  'rural': 'Rural',
};

class BusinessContextEditor extends StatefulWidget {
  const BusinessContextEditor(
      {super.key, required this.initial, required this.profile});

  final BusinessContext initial;
  final ShopProfile profile;

  @override
  State<BusinessContextEditor> createState() => _BusinessContextEditorState();
}

class _BusinessContextEditorState extends State<BusinessContextEditor> {
  late String? _primaryCode = widget.initial.primaryActivityCode;
  late String _primaryStatus = widget.initial.primaryActivityStatus;
  late String? _county = widget.initial.countyCode;
  late String _settlement = widget.initial.settlementContext;
  late Set<String> _roles = widget.initial.operatorRoles.toSet();
  late Set<String> _channels = widget.initial.salesChannels.toSet();
  late final Set<String> _secondary =
      widget.initial.secondaryActivityCodes.toSet();
  final TextEditingController _activitySearchController =
      TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _activitySearchController.dispose();
    super.dispose();
  }

  Map<String, String> get _activityOptions => {
        for (final activity in kesicActivities) activity.code: activity.label,
      };

  String _countyCode(int index) => (index + 1).toString().padLeft(3, '0');

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'primary_activity_code': _primaryCode,
      'secondary_activity_codes': _secondary,
      'operator_roles': _roles,
      'sales_channels': _channels,
      'county_code': _county,
      'settlement_context': _settlement,
    };
    final businessContext = BusinessContext(
      appProfile: widget.profile.wireValue,
      primaryActivityCode: _primaryCode,
      primaryActivityStatus: _primaryStatus,
      activityVersion: _primaryCode == null ? null : kesicReferenceVersion,
      secondaryActivityCodes: _secondary.toList()..sort(),
      operatorRoles: _roles.toList()..sort(),
      salesChannels: _channels.toList()..sort(),
      countyCode: _county,
      settlementContext: _settlement,
      fieldProvenance: {
        'app_profile': 'system_derived',
        'primary_activity_status': 'owner_confirmed',
        for (final entry in values.entries)
          if (entry.value != null &&
              entry.value != 'unknown' &&
              (entry.value is! Set || (entry.value as Set).isNotEmpty))
            entry.key: 'owner_confirmed',
      },
      confirmedAtUtc: now,
    );
    try {
      businessContext.validate();
      await DatabaseHelper.instance.saveBusinessContext(businessContext);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save details: $error')),
        );
      }
    }
  }

  Future<void> _chooseActivity({required bool secondary}) async {
    _activitySearchController.clear();
    final picked = await showDialog<KeSicActivity>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) {
          final term = _activitySearchController.text.trim().toLowerCase();
          final matches = kesicActivities
              .where((activity) =>
                  term.isEmpty ||
                  activity.code.contains(term) ||
                  activity.label.toLowerCase().contains(term) ||
                  activity.breadcrumb.toLowerCase().contains(term))
              .toList();
          return AlertDialog(
            title: Text(
                secondary ? 'Add a secondary activity' : 'Primary activity'),
            content: SizedBox(
              width: 520,
              height: 440,
              child: Column(children: [
                TextField(
                  controller: _activitySearchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Search KeSIC code or activity',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => refresh(() {}),
                ),
                const SizedBox(height: 8),
                Expanded(
                    child: ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final activity = matches[index];
                    return ListTile(
                      title: Text('${activity.code} · ${activity.label}'),
                      subtitle: Text(activity.breadcrumb),
                      onTap: () => Navigator.pop(dialogContext, activity),
                    );
                  },
                )),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              )
            ],
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (secondary) {
        if (picked.code != _primaryCode && _secondary.length < 4) {
          _secondary.add(picked.code);
        }
      } else {
        _primaryCode = picked.code;
        _primaryStatus = 'selected';
        _secondary.remove(picked.code);
      }
    });
  }

  Widget _dropdown(String label, String value, Map<String, String> options,
      ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map((entry) =>
              DropdownMenuItem(value: entry.key, child: Text(entry.value)))
          .toList(),
      onChanged: (next) {
        if (next != null) setState(() => onChanged(next));
      },
    );
  }

  Widget _multiChoice(String title, Map<String, String> options,
          Set<String> selected, ValueChanged<Set<String>> onChanged) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Wrap(
              spacing: 8,
              runSpacing: 2,
              children: options.entries
                  .map((entry) => FilterChip(
                        label: Text(entry.value),
                        selected: selected.contains(entry.key),
                        onSelected: (checked) {
                          final next = {...selected};
                          if (checked) {
                            next.add(entry.key);
                          } else {
                            next.remove(entry.key);
                          }
                          setState(() => onChanged(next));
                        },
                      ))
                  .toList()),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final screen = Scaffold(
      appBar: AppBar(title: const Text('Business details')),
      body: SafeArea(
          child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
              'Optional details describe this shop. When shop sync is enabled, '
              'they are saved to its operational record. This does not enable '
              'commercial contribution or partner sharing.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'POS profile'),
            child: Text(widget.profile.displayName),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Primary activity (KeSIC)'),
            subtitle: Text(_primaryCode == null
                ? (_primaryStatus == 'prefer_not_to_say'
                    ? 'Prefer not to say'
                    : 'Not sure yet — no code selected')
                : _primaryStatus == 'pending'
                    ? '${_primaryCode!} · pending review'
                    : '${_primaryCode!} · ${_activityOptions[_primaryCode] ?? 'Saved code'}'),
            trailing: const Icon(Icons.search),
            onTap: () => _chooseActivity(secondary: false),
          ),
          TextFormField(
            initialValue: _primaryStatus == 'pending' &&
                    _primaryCode != null &&
                    !isCachedKesicCode(_primaryCode!)
                ? _primaryCode
                : null,
            decoration: const InputDecoration(
              labelText: 'KeSIC code if you already know it',
              helperText:
                  'Unlisted or conflicting codes stay pending until verified.',
            ),
            textCapitalization: TextCapitalization.characters,
            onChanged: (value) => setState(() {
              final code = value.trim().toUpperCase();
              _primaryCode = code.isEmpty ? null : code;
              _primaryStatus = code.isEmpty
                  ? 'pending'
                  : isCachedKesicCode(code)
                      ? 'selected'
                      : 'pending';
            }),
          ),
          Wrap(spacing: 8, children: [
            TextButton(
              onPressed: () => setState(() {
                _primaryCode = null;
                _primaryStatus = 'pending';
              }),
              child: const Text('Not sure yet'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _primaryCode = null;
                _primaryStatus = 'prefer_not_to_say';
              }),
              child: const Text('Prefer not to say'),
            ),
          ]),
          Text(
              'Reference $kesicReferenceVersion · search the cached entries or leave your activity pending. '
              'Official reference: $kesicReferenceSource',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Text('Secondary activities (up to four)',
              style: Theme.of(context).textTheme.titleSmall),
          Wrap(
              spacing: 8,
              children: _secondary
                  .map((code) => InputChip(
                        label: Text(
                            '$code · ${_activityOptions[code] ?? 'Saved code'}'),
                        onDeleted: () =>
                            setState(() => _secondary.remove(code)),
                      ))
                  .toList()),
          OutlinedButton.icon(
            onPressed: _secondary.length >= 4
                ? null
                : () => _chooseActivity(secondary: true),
            icon: const Icon(Icons.add),
            label: const Text('Add secondary activity'),
          ),
          const SizedBox(height: 12),
          _multiChoice('Operator roles (optional)', _operatorLabels, _roles,
              (v) => _roles = v),
          const SizedBox(height: 12),
          _multiChoice('Sales channels (optional)', _channelLabels, _channels,
              (v) => _channels = v),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _county,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'County (optional)'),
            items: [
              const DropdownMenuItem<String?>(
                  value: null, child: Text('Not specified')),
              ...List.generate(
                  _counties.length,
                  (i) => DropdownMenuItem<String?>(
                      value: _countyCode(i),
                      child: Text('${_countyCode(i)} · ${_counties[i]}'))),
            ],
            onChanged: (value) => setState(() => _county = value),
          ),
          const SizedBox(height: 12),
          _dropdown('Settlement context', _settlement, _settlementLabels,
              (v) => _settlement = v),
          const SizedBox(height: 24),
          Semantics(
              liveRegion: true,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                child: Text(_saving ? 'Saving…' : 'Save business details'),
              )),
        ],
      )),
    );
    return screen;
  }
}
