import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/roles.dart';

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.value, required this.onChanged});

  final PermissionMode value;
  final ValueChanged<PermissionMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = <PermissionMode, String>{
      PermissionMode.allow: l10n.permissionsMatrixAllow,
      PermissionMode.approval: l10n.permissionsMatrixApproval,
      PermissionMode.deny: l10n.permissionsMatrixDeny,
    };
    return DropdownButton<PermissionMode>(
        value: value,
        isDense: true,
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
        items: [
          DropdownMenuItem(
              value: PermissionMode.allow, child: Text(labels[PermissionMode.allow]!)),
          DropdownMenuItem(
              value: PermissionMode.approval,
              child: Text(labels[PermissionMode.approval]!)),
          DropdownMenuItem(
              value: PermissionMode.deny, child: Text(labels[PermissionMode.deny]!)),
        ],
      );
  }
}

/// Owner-only runtime permission matrix for the two assignable roles.
class PermissionsMatrixScreen extends StatefulWidget {
  const PermissionsMatrixScreen({super.key});

  @override
  State<PermissionsMatrixScreen> createState() =>
      _PermissionsMatrixScreenState();
}

class _PermissionsMatrixScreenState extends State<PermissionsMatrixScreen> {
  bool _loading = true;
  String _role = ShopRole.manager.wire;
  int? _staffId;
  List<Staff> _staff = const [];
  Map<String, PermissionMode> _roleValues = <String, PermissionMode>{};
  Map<String, PermissionMode> _overrides = <String, PermissionMode>{};

  PermissionMode _mode(Map<String, dynamic> row) =>
      switch ((row['mode'] as String?)?.trim().toLowerCase()) {
        'allow' => PermissionMode.allow,
        'approval' => PermissionMode.approval,
        _ => (row['allowed'] as num?)?.toInt() == 1
            ? PermissionMode.allow
            : PermissionMode.deny,
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final matrix = await db.getPermissionMatrix();
    final staff = (await db.getStaff())
        .where((person) => person.active && person.id != null)
        .toList();
    if (!mounted) return;
    setState(() {
      _staff = staff;
      _roleValues = <String, PermissionMode>{
        for (final row in matrix)
          if (row['role'] == _role) row['permission'] as String: _mode(row),
      };
      _loading = false;
    });
  }

  Future<void> _loadOverrides(int? staffId) async {
    if (staffId == null) {
      setState(() {
        _staffId = null;
        _overrides = <String, PermissionMode>{};
      });
      return;
    }
    final rows =
        await DatabaseHelper.instance.getStaffPermissionOverrides(staffId);
    if (!mounted) return;
    setState(() {
      _staffId = staffId;
      _overrides = <String, PermissionMode>{
        for (final row in rows) row['permission'] as String: _mode(row),
      };
    });
  }

  Future<void> _setRole(String role) async {
    final rows = await DatabaseHelper.instance.getPermissionMatrix();
    if (!mounted) return;
    setState(() {
      _role = role;
      _roleValues = <String, PermissionMode>{
        for (final row in rows)
          if (row['role'] == role) row['permission'] as String: _mode(row),
      };
    });
  }

  Future<void> _setPermission(
      PermissionKey permission, PermissionMode value) async {
    await DatabaseHelper.instance.setRolePermissionMode(
      role: _role,
      permission: permission.wire,
      mode: value,
    );
    if (mounted) setState(() => _roleValues[permission.wire] = value);
  }

  Future<void> _setOverride(
      PermissionKey permission, PermissionMode value) async {
    final staffId = _staffId;
    if (staffId == null) return;
    await DatabaseHelper.instance.setStaffPermissionOverrideMode(
      staffId: staffId,
      permission: permission.wire,
      mode: value,
    );
    if (mounted) setState(() => _overrides[permission.wire] = value);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isOwnerSession) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).permissionsMatrixTitle)),
        body:
            Center(child: Text(AppLocalizations.of(context).permissionsMatrixOwnerOnly)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).permissionsMatrixTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(AppLocalizations.of(context).permissionsMatrixRolePermissions,
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'manager',
                        label: Text(AppLocalizations.of(context).permissionsMatrixManager)),
                    ButtonSegment(
                        value: 'cashier',
                        label: Text(AppLocalizations.of(context).permissionsMatrixCashier)),
                  ],
                  selected: {_role},
                  onSelectionChanged: (value) => _setRole(value.first),
                ),
                const SizedBox(height: 8),
                for (final permission in PermissionKey.values)
                  ListTile(
                    title: Text(permission.label),
                    trailing: _ModePicker(
                      value:
                          _roleValues[permission.wire] ?? PermissionMode.deny,
                      onChanged: (value) => _setPermission(permission, value),
                    ),
                  ),
                const Divider(height: 32),
                Text(AppLocalizations.of(context).permissionsMatrixStaffOverrides,
                    style: TextStyle(fontWeight: FontWeight.w700)),
                DropdownButtonFormField<int?>(
                  initialValue: _staffId,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).permissionsMatrixStaffMember),
                  items: [
                    DropdownMenuItem<int?>(
                        value: null,
                        child: Text(AppLocalizations.of(context)
                            .permissionsMatrixNoOverride)),
                    for (final person in _staff)
                      DropdownMenuItem<int?>(
                        value: person.id,
                        child: Text(person.name),
                      ),
                  ],
                  onChanged: _loadOverrides,
                ),
                if (_staffId != null)
                  for (final permission in PermissionKey.values)
                    ListTile(
                      title: Text(permission.label),
                      subtitle: Text(_overrides.containsKey(permission.wire)
                          ? AppLocalizations.of(context)
                              .permissionsMatrixIndividualOverride
                          : AppLocalizations.of(context).permissionsMatrixRoleDefault),
                      trailing: _overrides.containsKey(permission.wire)
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              _ModePicker(
                                value: _overrides[permission.wire]!,
                                onChanged: (value) =>
                                    _setOverride(permission, value),
                              ),
                              IconButton(
                                tooltip: AppLocalizations.of(context)
                                    .permissionsMatrixReset,
                                onPressed: () async {
                                  await DatabaseHelper.instance
                                      .clearStaffPermissionOverride(
                                          staffId: _staffId!,
                                          permission: permission.wire);
                                  if (mounted) {
                                    setState(() =>
                                        _overrides.remove(permission.wire));
                                  }
                                },
                                icon: const Icon(Icons.restart_alt),
                              ),
                            ])
                          : _ModePicker(
                              value: _roleValues[permission.wire] ??
                                  PermissionMode.deny,
                              onChanged: (value) =>
                                  _setOverride(permission, value),
                            ),
                    ),
              ],
            ),
    );
  }
}
