// Diagnostics: what the phone recorded when something went wrong.
//
// A shop owner's complaint is never "the app raised an exception". It is "it
// broke on Tuesday when I was printing" — and this screen is what turns the
// second into the first. Three things make that possible, and all three are why
// this is a panel rather than a text file:
//
//   1. THE ENTRY CARRIES ITS CONTEXT. Route, actor, what was being done, and
//      the trail of the last ten things that happened before the failure. Read
//      top-down, that is a reconstruction; a stack alone is a guess.
//
//   2. THE LOG IS BOUNDED AND SAYS SO. The count and the retained-row limit
//      are on screen, so "nothing since January" is visibly a cap rather than
//      a silent gap the owner might take as good news.
//
//   3. THE REPORT IS SHAREABLE AS TEXT. Copy is the action that leaves this
//      screen; nothing here uploads anywhere, because nothing knows where to
//      and because a shop's log is a shop's business.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../db/database_helper.dart';
import '../models/crash_log.dart';
import '../services/failure_recorder.dart';
import '../ui/components/brand_header.dart';
import '../theme/app_colors.dart';
import '../theme/app_haptics.dart';
import '../theme/app_spacing.dart';
import '../theme/typography.dart';
import '../ui/components/states.dart';
import '../ui/components/surface.dart';
import '../ui/layout/page.dart';

/// The panel, value-driven so it can be pumped without a database.
class DiagnosticsPanel extends StatelessWidget {
  const DiagnosticsPanel({
    required this.entries,
    required this.loading,
    required this.onClear,
    required this.onCopyReport,
    required this.onRefresh,
    this.retainedRows = 200,
    this.message,
    this.failed = false,
    super.key,
  });

  /// The failure log, newest first.
  final List<CrashLogEntry> entries;

  final bool loading;

  final Future<void> Function() onClear;

  /// Puts the report on the clipboard and reports the outcome, which is why it
  /// is the caller's call and not the panel's: only the caller has the text.
  final Future<void> Function() onCopyReport;

  final Future<void> Function() onRefresh;

  /// The cap, shown so a shop can tell a trimmed log from an empty one.
  final int retainedRows;

  /// The last thing that happened, as a message: copied, cleared, refreshed.
  final String? message;

  /// True when the log could not be read at all.
  ///
  /// Distinct from an empty log, which is good news: a shop whose failure log
  /// will not load needs to hear that, not "nothing has gone wrong".
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AdaptivePage(
      // NOT scrollable: the list scrolls itself, and a scroll view wrapping a
      // 200-card column built every one of those cards on the first frame.
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (loading)
            // A spinner, not the shared skeleton list: the skeleton is built
            // for a list that is about to arrive, and it reads an inherited
            // widget during its own initState, which the framework rejects
            // when the skeleton appears on a frame that also rebuilds its
            // ancestors. A plain indicator is the honest "one moment".
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (failed)
            // A log that could not be read must not read as an empty one: the
            // whole point of this screen is to say what broke, and an
            // unreadable failure log is exactly when an owner needs it.
            EmptyStateView(
              title: l10n.diagnosticsUnreadableTitle,
              message: l10n.diagnosticsUnreadableMessage,
              actionLabel: l10n.actionRefresh,
              onAction: () => onRefresh(),
            )
          else if (entries.isEmpty)
            EmptyStateView(
              title: l10n.diagnosticsEmptyTitle,
              message: l10n.diagnosticsEmptyMessage,
              actionLabel: l10n.actionRefresh,
              onAction: () => onRefresh(),
            )
          else ...<Widget>[
            _DiagnosticsHeader(
                count: entries.length, retainedRows: retainedRows),
            Expanded(
              // LAZY: up to 200 entries, each holding a full stack trace. Only
              // the visible ones are built, so opening this screen — and every
              // setState afterwards — no longer constructs all of them.
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, __) =>
                    SizedBox(height: AppSpacing.of(context).sm),
                itemBuilder: (BuildContext context, int i) =>
                    _FailureCard(entry: entries[i]),
              ),
            ),
          ],
          SizedBox(height: AppSpacing.of(context).md),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: entries.isEmpty ? null : () => onCopyReport(),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: Text(l10n.diagnosticsCopyReport),
                ),
              ),
              SizedBox(width: AppSpacing.of(context).sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: entries.isEmpty ? null : () => onClear(),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.diagnosticsClear),
                ),
              ),
            ],
          ),
          if (message != null) ...<Widget>[
            SizedBox(height: AppSpacing.of(context).md),
            Semantics(
              liveRegion: true,
              child: Text(
                message!,
                style: AppTypography.of(context)
                    .bodySmall
                    ?.copyWith(color: AppColors.of(context).onSurfaceMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The count and the cap, together, on purpose.
class _DiagnosticsHeader extends StatelessWidget {
  const _DiagnosticsHeader({required this.count, required this.retainedRows});

  final int count;
  final int retainedRows;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppColors colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.diagnosticsRecentTitle,
            style: AppTypography.of(context).titleMedium),
        SizedBox(height: AppSpacing.of(context).xs),
        Text(
          // Generated params are ordered alphabetically — `cap, count, days` —
          // so the arguments must follow the same order or the numbers swap
          // silently. See the gotcha in HANDOFF.md.
          l10n.diagnosticsRecentCount(retainedRows, count, 2),
          style: AppTypography.of(context)
              .bodySmall
              ?.copyWith(color: colors.onSurfaceMuted),
        ),
      ],
    );
  }
}

/// One failure, with everything that makes it reconstructable.
class _FailureCard extends StatefulWidget {
  const _FailureCard({required this.entry});

  final CrashLogEntry entry;

  @override
  State<_FailureCard> createState() => _FailureCardState();
}

class _FailureCardState extends State<_FailureCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final CrashLogEntry entry = widget.entry;
    final AppColors colors = AppColors.of(context);
    final AppSpacing spacing = AppSpacing.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme type = AppTypography.of(context);

    // A card of its own, with an `onTap` that is the whole row rather than a
    // chevron: the target has to be findable with a thumb.
    return SurfaceCard(
      padding: EdgeInsets.zero,
      onTap: () => setState(() => _expanded = !_expanded),
      semanticLabel: '${entry.kind.wire}: ${entry.message}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            // The whole row is the target: a tap that only works on a small
            // chevron is a tap target nobody can hit with a thumb.
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: EdgeInsets.all(spacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(_iconFor(entry.kind),
                      size: 20, color: _colorFor(context, entry.kind)),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(entry.message, style: type.bodyMedium),
                        SizedBox(height: spacing.xs),
                        Text(
                          l10n.diagnosticsEntryContext(
                            entry.action ?? l10n.diagnosticsActionUnknown,
                            entry.actorName ?? l10n.diagnosticsActorUnknown,
                            entry.route ?? l10n.diagnosticsRouteUnknown,
                          ),
                          style: type.bodySmall
                              ?.copyWith(color: colors.onSurfaceMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                  spacing.md, 0, spacing.md, spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (entry.breadcrumbs.isNotEmpty) ...<Widget>[
                    Text(l10n.diagnosticsTrailTitle, style: type.labelLarge),
                    SizedBox(height: spacing.xs),
                    Text(entry.breadcrumbs.join(' › '), style: type.bodySmall),
                    SizedBox(height: spacing.sm),
                  ],
                  if (entry.stack != null &&
                      entry.stack!.isNotEmpty) ...<Widget>[
                    Text(l10n.diagnosticsStackTitle, style: type.labelLarge),
                    SizedBox(height: spacing.xs),
                    // Selectable, because the one thing a developer asks a shop
                    // owner for is a copy of this.
                    SelectableText(
                      entry.stack!,
                      style: type.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(CrashKind kind) => switch (kind) {
        CrashKind.crash => Icons.error_outline,
        CrashKind.error => Icons.warning_amber_outlined,
        CrashKind.warning => Icons.info_outline,
      };

  Color _colorFor(BuildContext context, CrashKind kind) {
    final AppColors colors = AppColors.of(context);
    // Never colour alone: the icon's shape changes with the kind, so a
    // colour-blind reader still tells a crash from a notice.
    return switch (kind) {
      CrashKind.crash => colors.danger,
      CrashKind.error => colors.warning,
      CrashKind.warning => colors.onSurfaceMuted,
    };
  }
}

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    required this.loadEntries,
    required this.onClearLog,
    required this.environment,
    super.key,
  });

  final Future<List<CrashLogEntry>> Function() loadEntries;

  final Future<void> Function() onClearLog;

  final Map<String, String> environment;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class DiagnosticsScreenOpen extends DiagnosticsScreen {
  DiagnosticsScreenOpen({super.key})
      : super(
          loadEntries: () async =>
              DatabaseHelper.instance.crashLog(const CrashLogQuery(limit: 200)),
          onClearLog: () async => DatabaseHelper.instance.clearCrashLog(),
          // Not const, and deliberately so: the environment is read from the
          // platform at build time, and a const map of platform facts is a map
          // of whatever was true when the app started.
          environment: FailureRecorder().environment(),
        );
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<CrashLogEntry> _entries = <CrashLogEntry>[];
  bool _loading = true;

  bool _failed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Loaded, not passed in: a screen that must be constructed with data it
    // then cannot refresh is a screen that shows the same three rows forever.
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final List<CrashLogEntry> entries = await widget.loadEntries();
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (_) {
      // An unreadable log is a failure in its own right, and saying so is the
      // difference between a shop that reports the bug and one that believes
      // nothing is broken. Uncaught, this escaped as an unhandled async error
      // from the `unawaited(_load())` in initState.
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyReport() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: _report()));
    if (!mounted) return;
    HapticTheme.of(context).fire(HapticEvent.commit);
    setState(() => _message = l10n.diagnosticsReportCopied);
  }

  Future<void> _clear() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // A confirmation, because the log is the diagnosis and losing it is not
    // recoverable from the phone.
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.diagnosticsClearConfirmTitle),
        content: Text(l10n.diagnosticsClearConfirmMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.actionConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await widget.onClearLog();
    await _load();
    if (!mounted) return;
    HapticTheme.of(context).fire(HapticEvent.commit);
    setState(() => _message = l10n.diagnosticsCleared);
  }

  String _report() {
    final StringBuffer out = StringBuffer()
      ..writeln('SimpleSales failure report');
    for (final MapEntry<String, String> field in widget.environment.entries) {
      out.writeln('${field.key}: ${field.value}');
    }
    out.writeln('entries: ${_entries.length}');
    for (final CrashLogEntry entry in _entries) {
      out
        ..writeln('')
        ..writeln('[${entry.at}] ${entry.kind.wire}: ${entry.message}')
        ..writeln(
            'route: ${entry.route ?? '-'} · actor: ${entry.actorName ?? '-'} · action: ${entry.action ?? '-'}');
      if (entry.breadcrumbs.isNotEmpty) {
        out.writeln('trail: ${entry.breadcrumbs.join(' > ')}');
      }
      if (entry.stack != null && entry.stack!.isNotEmpty) {
        out.writeln(entry.stack);
      }
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: BrandHeader(
          title: Text(l10n.diagnosticsTitle),
        ),
      ),
      // The whole screen: the panel scrolls, so the keyboard must not resize
      // it out from under an open card.
      body: DiagnosticsPanel(
        entries: _entries,
        loading: _loading,
        message: _message,
        failed: _failed,
        // The cap is the database's, and the panel shows it so a shop can tell
        // a trimmed log from an empty one.
        retainedRows: DatabaseHelper.crashRetainRows,
        onCopyReport: _copyReport,
        onClear: _clear,
        onRefresh: _load,
      ),
    );
  }
}
