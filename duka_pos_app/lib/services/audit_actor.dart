/// Who to credit an action to.
///
/// Every state-changing thing in the app is attributed, and the attribution is
/// resolved ONCE from the session rather than at each call site — a screen that
/// decided for itself whether the actor was the owner would eventually disagree
/// with the screen next to it, and "who changed this" is not a question that
/// can have two answers.
library;

import '../db/database_helper.dart';
import '../models/audit_log.dart';
import 'app_state.dart';

class AuditActor {
  const AuditActor._({required this.id, required this.name});

  /// The owner. Null id, by design: `deleteStaffWithTombstone` anonymises the
  /// staff table, and an audit row keyed to a row that may be scrubbed would
  /// leak the very name the tombstone exists to remove.
  factory AuditActor.owner(AppState state) {
    final owner = state.owner;
    return AuditActor._(
      id: null,
      name: owner?.name ?? 'Owner',
    );
  }

  /// A signed-in member of staff.
  ///
  /// The id comes from the SESSION (`currentStaffId`), which is the one value
  /// the login already established. The previous version resolved the id by
  /// MATCHING THE DISPLAY NAME back through the staff table, which had two
  /// failure modes: a name that matched nothing wrote `actor_id = NULL`, the
  /// same value the owner path writes, so a cashier's action read as an
  /// owner's action; and a name matching more than one row attributed to
  /// whichever came back first. `username` is unique in the schema, `name` is
  /// not.
  static AuditActor staff(AppState state) {
    final name = state.currentStaffName ?? state.owner?.name ?? 'Unknown';
    return AuditActor._(id: state.currentStaffId, name: name);
  }

  final int? id;

  final String name;

  /// The actor recorded on a deletion's own audit row.
  ///
  /// Named, because the actor name on every other row has just been encrypted —
  /// this one has no one left to attribute to, and writing a real name here
  /// would be the single personal value the erasure left behind. The id is null,
  /// which reads as an owner row, and that is right: the owner is who deletes.
  static AuditActor deleted() => const AuditActor._(
        id: null,
        name: 'account deleted',
      );

  /// The actor for whichever session is current.
  ///
  /// Synchronous now that the actor is resolved from the session rather than
  /// matched back through the staff table: an audit write costs no extra query,
  /// which matters because every sale writes one.
  static AuditActor current(AppState state) =>
      state.isOwnerSession ? AuditActor.owner(state) : AuditActor.staff(state);

  AuditLogEntry entry(
    AuditAction action,
    AuditEntity entity, {
    String? entityId,
    String? detail,
    String? createdAt,
  }) =>
      AuditLogEntry(
        action: action,
        entity: entity,
        entityId: entityId,
        actorId: id,
        actorName: name,
        detail: detail,
        createdAt: createdAt ?? DateTime.now().toIso8601String(),
      );
}

/// The row an action will write, without writing it.
///
/// The counterpart to [recordActionAudit] for an action that produces SEVERAL
/// rows: build them all, then write them together in one transaction with
/// `DatabaseHelper.recordAudits`. One gesture then costs one disk commit
/// instead of one per row — the variant save on the inventory screen used to
/// issue four to eight separate audit transactions.
AuditLogEntry recordAuditEntry(
  AppState state, {
  required AuditAction action,
  required AuditEntity entity,
  String? entityId,
  String? detail,
}) =>
    AuditActor.current(state).entry(
      action,
      entity,
      entityId: entityId,
      detail: detail,
    );

/// Records one action, attributed to whoever is signed in.
///
/// Free rather than a method on a screen's state because two widgets write audit
/// rows — the inventory screen and the product editor sheet — and a copy in each
/// would be two attribution rules to keep in step.
///
/// Takes the [AppState] rather than a `BuildContext` deliberately: the session
/// is the thing that knows who is signed in, and holding a context across an
/// `await` is exactly what `use_build_context_synchronously` forbids. A caller
/// reads its state once, before its first await, and passes it here.
///
/// Swallows its failure deliberately: the action it logs has already happened
/// and already persisted. A shop that could not adjust its stock because a log
/// insert failed is in a worse state than a shop with a gap in its log.
Future<void> recordActionAudit(
  AppState state, {
  required AuditAction action,
  required AuditEntity entity,
  String? entityId,
  String? detail,
}) async {
  try {
    await DatabaseHelper.instance.recordAudit(
      recordAuditEntry(
        state,
        action: action,
        entity: entity,
        entityId: entityId,
        detail: detail,
      ),
    );
  } catch (_) {
    // Intentionally unreported: see the doc comment above.
  }
}
