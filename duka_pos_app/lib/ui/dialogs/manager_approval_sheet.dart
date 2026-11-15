// Who approved this? — the reusable approval sheet.
//
// ## WHAT THIS IS FOR
//
// The permission model names a single shape of escalation: a CASHIER runs
// into a wall, and a manager or the owner clears it then and there — without
// signing the cashier out and losing the cart. The wall stays where it is:
// what changes is that the action is recorded with WHO cleared it.
//
// The sheet answers exactly one question: WHO a manager is, by the manager's
// own PIN. It never signs anyone in or out. The caller receives a Staff row
// they write into the ledger and the audit.
//
// ## WHY THE APPROVER PICKS THEMSELF, THEN TYPES ONLY THEIR PIN
//
// One shared till is the whole reason approvals exist: the person clearing
// the wall is NOT the person at the screen. Their PIN is the proof, and it is
// theirs alone.
//
// ## WHY "TYPE WRONG" IS PLAIN
//
// The sign-in screen throttles guesses; here the approver is standing at the
// till and every failure is shown on the sheet — three wrong taps and the
// approver types again slowly, which is exactly how a real supervisor works.
// No silent lockout to confuse a shared till; see P0-12 for why sign-in is
// different (credential caches).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../db/database_helper.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/typography.dart';
import '../../ui/components/controls.dart';
import '../../ui/components/status.dart';

/// Asks a manager or the owner to approve, by picking their name and typing
/// their PIN.
///
/// [purpose] is one line under the title, saying WHAT is being approved —
/// "That sale would take Mary Wanjiku past their credit limit", never a
/// generic "Approval required". The approver is agreeing to a specific thing,
/// and is told what it is.
///
/// Closes with a [Staff] whose PIN checked, or null. Null is DECLINE,
/// dismissal, or "no manager on the books" — never an approval. Callers must
/// treat null as "the approval did not happen" and not write it anywhere.
Future<Staff?> showManagerApprovalSheet(
  BuildContext context, {
  required String purpose,
}) {
  return showModalBottomSheet<Staff>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) =>
        ManagerApprovalSheet(purpose: purpose),
  );
}

class ManagerApprovalSheet extends StatefulWidget {
  const ManagerApprovalSheet({required this.purpose, super.key});

  final String purpose;

  @override
  State<ManagerApprovalSheet> createState() => _ManagerApprovalSheetState();
}

class _ManagerApprovalSheetState extends State<ManagerApprovalSheet>
    with AutomaticKeepAliveClientMixin {
  /// The people who could approve this: managers and the owner, active.
  List<Staff> _approvers = const [];
  String? _error;
  bool _loading = true;
  bool _checking = false;

  Staff? _chosen;
  String _typed = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Staff> staff = await DatabaseHelper.instance.getStaff();
    if (!mounted) return;
    setState(() {
      _approvers = [
        for (final Staff person in staff)
          if (person.active &&
              (person.role == 'manager' || person.role == 'admin'))
            person,
      ];
      _loading = false;
      // A shop with nobody who could approve says so, plainly.
      if (_approvers.isEmpty) {
        _error = AppLocalizations.of(context).approvalNoManagers;
      }
    });
  }

  Future<void> _submit() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Staff? chosen = _chosen;
    if (chosen == null || _typed.length != 6 || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final String? hash =
          await DatabaseHelper.instance.staffPinHash(chosen.id!);
      final bool ok = hash != null && await AuthService.verifyPin(_typed, hash);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _checking = false;
          _typed = '';
          _error = l10n.approvalWrongPin;
        });
        return;
      }
      // The record: the caller stores the approver's id on the action, and
      // the audit names them beside it. Nothing here is kept.
      Navigator.of(context).pop(chosen);
    } on StateError {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _typed = '';
        _error = l10n.approvalWrongPin;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final TextTheme type = AppTypography.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(spacing.lg, spacing.lg, spacing.lg,
            spacing.lg + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l10n.approvalTitle, style: type.titleLarge),
            SizedBox(height: spacing.xs),
            Text(widget.purpose, style: type.bodyMedium),
            SizedBox(height: spacing.md),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_approvers.isEmpty) ...<Widget>[
              // Nobody could approve: say so, and offer nothing else. A PIN
              // field that can never succeed is dead UI — there is nobody
              // on the list to pick, so no PIN can ever be checked.
              SizedBox(height: spacing.xs),
              PersistentBanner(
                tone: StatusTone.danger,
                icon: Icons.error_outline,
                message: l10n.approvalNoManagers,
              ),
            ] else ...<Widget>[
              // WHO. Straight from the staff list — "selects their name".
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final Staff person in _approvers)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        selected: _chosen?.id == person.id,
                        leading: Icon(
                          person.role == 'admin'
                              ? Icons.shield_outlined
                              : Icons.badge_outlined,
                          color: colors.accent,
                        ),
                        title: Text(person.name, style: type.bodyLarge),
                        subtitle: Text(
                          person.role == 'admin'
                              ? l10n.roleNameOwner
                              : person.role == 'manager'
                                  ? l10n.roleNameManager
                                  : l10n.roleNameCashier,
                          style: type.bodySmall
                              ?.copyWith(color: colors.onSurfaceMuted),
                        ),
                        onTap: () {
                          setState(() {
                            _chosen = person;
                            _typed = '';
                            _error = null;
                          });
                          FocusScope.of(context).unfocus();
                        },
                      ),
                  ],
                ),
              ),
              SizedBox(height: spacing.sm),
              // THE PIN. Same discipline as the till's sign-in: six digits,
              // no suggestion, no autocorrect, nothing kept after.
              TextField(
                autofocus: true,
                enableSuggestions: false,
                autocorrect: false,
                obscuringCharacter: '•',
                obscureText: true,
                enabled: !_checking,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (String _) => _submit(),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (String value) {
                  setState(() => _typed = value);
                  // The check starts itself at the last digit: a PIN is six
                  // exactly, so waiting for a "submit" would be ceremony.
                  if (value.length == 6) _submit();
                },
                decoration: InputDecoration(
                  labelText: l10n.approvalPinLabel,
                  suffixIcon: _checking
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ),
              if (_error != null) ...<Widget>[
                SizedBox(height: spacing.sm),
                PersistentBanner(
                  tone: StatusTone.danger,
                  icon: Icons.error_outline,
                  message: _error!,
                ),
              ],
              SizedBox(height: spacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _checking
                          ? null
                          : () => Navigator.of(context).pop(null),
                      child: Text(l10n.actionCancel),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          _checking || _typed.length < 6 ? null : _submit,
                      child: Text(l10n.approvalConfirmAction),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
