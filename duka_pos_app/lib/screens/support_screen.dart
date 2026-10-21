/// Support: where a shopkeeper tells us what is broken and what they need next.
///
/// Two lists, one form each:
///
///   * **Support tickets** — "my printer will not connect", "the till froze at
///     lunchtime". A ticket has a title, a description, and a status
///     (open → in progress → resolved).
///   * **Feature requests** — "I need M-Pesa on the second till", "show me last
///     month's profit by product". A request has a title and a description.
///
/// Both are stored locally on this phone in [SharedPreferences]. They are not
/// sent anywhere yet: a support system that phones home without asking is
/// spyware, not support. When a backend exists, the same screens submit to it.
///
/// One screen, reachable from the shell by anyone who can sell — a cashier
/// filing a ticket is not an admin action.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/telemetry_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/screen_title.dart';
import '../ui/components/status.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';

/// A support ticket or a feature request: one thing a shopkeeper wants.
///
/// Stored as a JSON map in shared_preferences, keyed under
/// `_kSupportTickets` or `_kFeatureRequests`. A real backend replaces the
/// storage later; the screen never changes.
@immutable
class SupportItem {
  const SupportItem({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    this.status = 'open',
  });

  final String id;
  final String title;
  final String description;
  final String createdAt;
  final String status;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'title': title,
        'description': description,
        'createdAt': createdAt,
        'status': status,
      };

  static SupportItem fromMap(Map<String, dynamic> m) => SupportItem(
        id: m['id'] as String,
        title: m['title'] as String,
        description: m['description'] as String,
        createdAt: m['createdAt'] as String,
        status: (m['status'] as String? ?? 'open'),
      );
}

/// The key under which support tickets are stored.
const String _kSupportTickets = 'support_tickets';

/// The key under which feature requests are stored.
const String _kFeatureRequests = 'support_feature_requests';

/// Owns the support items: reading, writing, listing.
///
/// A `ChangeNotifier` so the screen rebuilds when a new item is added, and a
/// singleton so the submit form and the list share one store.
class SupportService extends ChangeNotifier {
  SupportService() {
    _load();
  }

  /// The shared preferences instance, loaded lazily on first use.
  late final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();

  final List<SupportItem> _tickets = <SupportItem>[];
  final List<SupportItem> _requests = <SupportItem>[];

  List<SupportItem> get tickets => List.unmodifiable(_tickets);
  List<SupportItem> get requests => List.unmodifiable(_requests);

  bool _busy = false;
  bool get busy => _busy;

  Future<void> _load() async {
    final prefs = await _prefsFuture;
    for (final raw in (prefs.getStringList(_kSupportTickets) ?? <String>[])) {
      try {
        _tickets
            .add(SupportItem.fromMap(jsonDecode(raw) as Map<String, dynamic>));
      } on Object {
        // A corrupt ticket is skipped, not fatal.
      }
    }
    for (final raw in (prefs.getStringList(_kFeatureRequests) ?? <String>[])) {
      try {
        _requests
            .add(SupportItem.fromMap(jsonDecode(raw) as Map<String, dynamic>));
      } on Object {
        // A corrupt request is skipped, not fatal.
      }
    }
    notifyListeners();
  }

  Future<void> _persist(String key, List<SupportItem> items) async {
    final prefs = await _prefsFuture;
    await prefs.setStringList(
      key,
      items.map((item) => jsonEncode(item.toMap())).toList(),
    );
  }

  /// File a support ticket. Never throws.
  Future<void> fileTicket({
    required String title,
    required String description,
  }) async {
    if (title.trim().isEmpty || description.trim().isEmpty) return;
    _busy = true;
    notifyListeners();
    try {
      final item = SupportItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title.trim(),
        description: description.trim(),
        createdAt: DateTime.now().toIso8601String(),
        status: 'open',
      );
      _tickets.insert(0, item);
      await _persist(_kSupportTickets, _tickets);
      telemetry.recordFeatureUse('support_ticket_filed', detail: title);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// File a feature request. Never throws.
  Future<void> fileRequest({
    required String title,
    required String description,
  }) async {
    if (title.trim().isEmpty || description.trim().isEmpty) return;
    _busy = true;
    notifyListeners();
    try {
      final item = SupportItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title.trim(),
        description: description.trim(),
        createdAt: DateTime.now().toIso8601String(),
        status: 'open',
      );
      _requests.insert(0, item);
      await _persist(_kFeatureRequests, _requests);
      telemetry.recordFeatureUse('feature_request_filed', detail: title);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Mark an item as resolved.
  Future<void> resolveItem(String key, String id) async {
    final list = key == _kSupportTickets ? _tickets : _requests;
    final index = list.indexWhere((item) => item.id == id);
    if (index == -1) return;
    list[index] = SupportItem(
      id: list[index].id,
      title: list[index].title,
      description: list[index].description,
      createdAt: list[index].createdAt,
      status: 'resolved',
    );
    await _persist(key, list);
    notifyListeners();
  }
}

/// The singleton. Every part of the app that reads or writes support items
/// uses this one instance.
final SupportService support = SupportService();

/// The support screen: tickets and feature requests, side by side.
///
/// Reachable by anyone who can sell — a cashier filing a ticket is not an
/// admin action, so it is its own destination rather than hiding inside
/// Settings.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _submittingTicket = false;
  bool _submittingRequest = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spacing = AppSpacing.of(context);

    return AdaptivePage(
      scrollable: true,
      padding: EdgeInsets.all(spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The screen's NAME, large and on the canvas. The brand lockup that
          // used to sit here spent the first line of the screen on the
          // product's name instead of on the thing the shopkeeper came to do.
          ScreenTitle(
            title: l10n.supportTitle,
            padding: EdgeInsetsDirectional.only(
              top: spacing.sm,
              bottom: spacing.lg,
            ),
          ),
          // ---- Support tickets ----
          _SectionCard(
            title: l10n.supportTicketsSection,
            subtitle: l10n.supportTicketsSubtitle,
            icon: Icons.help_outline,
            children: <Widget>[
              _ItemList(
                items: support.tickets,
                emptyMessage: l10n.supportNoTickets,
                onResolve: (id) => support.resolveItem(_kSupportTickets, id),
              ),
              SizedBox(height: spacing.lg),
              _SubmitForm(
                label: l10n.supportFileTicketLabel,
                hint: l10n.supportTicketHint,
                submitLabel: l10n.supportFileTicketAction,
                submitting: _submittingTicket,
                onSubmit: (title, description) async {
                  setState(() => _submittingTicket = true);
                  await support.fileTicket(
                      title: title, description: description);
                  if (mounted) setState(() => _submittingTicket = false);
                },
              ),
            ],
          ),
          SizedBox(height: spacing.md),
          // ---- Feature requests ----
          _SectionCard(
            title: l10n.supportFeatureRequestsSection,
            subtitle: l10n.supportFeatureRequestsSubtitle,
            icon: Icons.lightbulb_outline,
            children: <Widget>[
              _ItemList(
                items: support.requests,
                emptyMessage: l10n.supportNoRequests,
                onResolve: (id) => support.resolveItem(_kFeatureRequests, id),
              ),
              SizedBox(height: spacing.lg),
              _SubmitForm(
                label: l10n.supportFileRequestLabel,
                hint: l10n.supportRequestHint,
                submitLabel: l10n.supportFileRequestAction,
                submitting: _submittingRequest,
                onSubmit: (title, description) async {
                  setState(() => _submittingRequest = true);
                  await support.fileRequest(
                      title: title, description: description);
                  if (mounted) setState(() => _submittingRequest = false);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One section: a header, the list of items, and the form to add one.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);

    return SurfaceCard(
      padding: EdgeInsets.zero,
      clipContent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: spacing.xl,
              end: spacing.md,
              top: spacing.sm,
              bottom: spacing.sm,
            ),
            child: Row(
              children: <Widget>[
                // The tonal badge that marks a section: a circle, so the eye
                // reads it as a marker and moves on to the words.
                IconBadge(icon: icon),
                SizedBox(width: spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: AppTypography.of(context).titleMedium,
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        subtitle,
                        style: AppTypography.of(context).bodySmall?.copyWith(
                              color: colors.onSurfaceMuted,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outline),
          ...children,
        ],
      ),
    );
  }
}

/// A list of support items: each row is title, description, status chip.
class _ItemList extends StatelessWidget {
  const _ItemList({
    required this.items,
    required this.emptyMessage,
    required this.onResolve,
  });

  final List<SupportItem> items;
  final String emptyMessage;
  final ValueChanged<String> onResolve;

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    final colors = AppColors.of(context);

    if (items.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(spacing.xl),
        child: Row(
          children: <Widget>[
            Icon(Icons.info_outline, size: 20, color: colors.onSurfaceMuted),
            SizedBox(width: spacing.md),
            Expanded(
              child: Text(
                emptyMessage,
                style: AppTypography.of(context).bodyMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, color: colors.outline));
      }
      rows.add(_ItemRow(item: items[i], onResolve: onResolve));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// One item row: title, description, status, resolve button.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.onResolve,
  });

  final SupportItem item;
  final ValueChanged<String> onResolve;

  StatusTone _tone(String status) => switch (status) {
        'open' => StatusTone.warning,
        'in_progress' => StatusTone.pending,
        'resolved' => StatusTone.success,
        _ => StatusTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);

    final bool resolved = item.status == 'resolved';

    return InkWell(
      onTap: resolved ? null : () => onResolve(item.id),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: spacing.xl,
          end: spacing.xl,
          top: spacing.md,
          bottom: spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Semantics(
                        header: true,
                        child: Text(
                          item.title,
                          style: type.bodyMedium?.copyWith(
                            color: resolved ? colors.onSurfaceMuted : null,
                            decoration:
                                resolved ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        item.description,
                        style: type.bodySmall?.copyWith(
                          color: resolved ? colors.onSurfaceMuted : null,
                          decoration:
                              resolved ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: spacing.md),
                StatusChip(
                  tone: _tone(item.status),
                  text: item.status == 'resolved'
                      ? 'Resolved'
                      : item.status == 'in_progress'
                          ? 'In progress'
                          : 'Open',
                ),
              ],
            ),
            if (!resolved) ...<Widget>[
              SizedBox(height: spacing.md),
              Align(
                // Directional, so the action sits on the END side of the row in
                // every locale — a physically-right-aligned button is a button
                // in the wrong corner for half the world's readers.
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => onResolve(item.id),
                  child: Text('Mark resolved'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A form with two fields and a submit button.
class _SubmitForm extends StatefulWidget {
  const _SubmitForm({
    required this.label,
    required this.hint,
    required this.submitLabel,
    required this.submitting,
    required this.onSubmit,
  });

  final String label;
  final String hint;
  final String submitLabel;
  final bool submitting;
  final Future<void> Function(String title, String description) onSubmit;

  @override
  State<_SubmitForm> createState() => _SubmitFormState();
}

class _SubmitFormState extends State<_SubmitForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    final l10n = AppLocalizations.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return l10n.validationFieldRequired('field');
              }
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          SizedBox(height: spacing.md),
          TextFormField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: l10n.supportDescriptionLabel,
              hintText: l10n.supportDescriptionHint,
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return l10n.validationFieldRequired('field');
              }
              return null;
            },
            maxLines: 4,
            textInputAction: TextInputAction.done,
          ),
          SizedBox(height: spacing.lg),
          FilledButton(
            onPressed: widget.submitting ? null : _submit,
            child: widget.submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.onSubmit(
      _titleController.text.trim(),
      _descriptionController.text.trim(),
    );
    _titleController.clear();
    _descriptionController.clear();
  }
}
